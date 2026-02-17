/**
 * Causal Graph Editor Module
 * Cytoscape.js + ELK layout for evidence-based bruxism causal network
 */

import * as storage from './storage.js';

import { DEFAULT_GRAPH_DATA } from './causalEditor/defaultGraphData.js';
import { CYTOSCAPE_STYLES } from './causalEditor/cytoscapeStyles.js';
import {
    NODE_TIERS,
    TIER_LABELS,
    NUM_TIERS,
    INTERVENTION_COLUMNS,
    INTERVENTION_CATEGORIES,
} from './causalEditor/layoutConfig.js';
import { buildInterventionMaps } from './causalEditor/interventionMaps.js';
import { EFFECTIVENESS_WEIGHTS, CASCADE_DECAY } from './causalEditor/defenseConstants.js';
import {
    computeNetworkImpact,
    computeDefenseScores,
    scoreToColor,
    scoreToLabel,
} from './causalEditor/defenseScoring.js';

// ═══════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════

const runtimeDocument = typeof document !== 'undefined' ? document : null;
const runtimeWindow = typeof window !== 'undefined' ? window : null;

const GRAPH_CONFIGS = [
    { containerId: 'causal-graph', cyContainerId: 'causal-graph-cy' },
];

let currentGraphData = null;
let showInterventions = false; // Interventions hidden by default
let showFeedbackEdges = false;  // Feedback edges hidden by default
let showProtectiveEdges = false; // Protective mechanism edges hidden by default
let showDefenseMode = true;    // Defense heatmap mode active by default
let pinnedInterventions = new Set(); // Pinned intervention node IDs for highlight persistence
let pinnedNode = null;  // Currently pinned regular node ID (only one at a time)
let _checkinFilterNodeId = null;  // node ID to filter check-in panel by (null = show all)

// Cytoscape instance tracking (container ID string → cy instance)
const cyInstances = new Map();

// Tooltip element (shared singleton)
let tooltipEl = null;

// Threat edge marching ants interval
let _threatEdgeInterval = null;

// Previous shield tier (for level-up detection)
let _prevShieldTier = null;

// Activity feed entries (persists across sidebar re-renders)
const _activityFeed = [];

// ═══════════════════════════════════════════════════════════
// GAMIFICATION CONSTANTS
// ═══════════════════════════════════════════════════════════

const SHIELD_TIERS = [
    { min: 90, label: 'Impervious', css: 'tier-impervious', color: '#fbbf24' },
    { min: 75, label: 'Fortified',  css: 'tier-fortified',  color: '#4ade80' },
    { min: 50, label: 'Protected',  css: 'tier-protected',  color: '#22c55e' },
    { min: 25, label: 'Guarded',    css: 'tier-guarded',    color: '#f59e0b' },
    { min: 0,  label: 'Exposed',    css: 'tier-exposed',    color: '#ef4444' },
];

function getShieldTier(rating) {
    return SHIELD_TIERS.find(t => rating >= t.min) || SHIELD_TIERS[SHIELD_TIERS.length - 1];
}

// ═══════════════════════════════════════════════════════════
// TOAST NOTIFICATIONS
// ═══════════════════════════════════════════════════════════

function showToastNotification(message, cssClass = '', { html = false, duration = 2500 } = {}) {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = 'toast' + (cssClass ? ' ' + cssClass : '');
    if (html) {
        toast.innerHTML = message;
    } else {
        toast.textContent = message;
    }
    container.appendChild(toast);
    setTimeout(() => {
        toast.classList.add('toast-out');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// ═══════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════

export function initCausalEditor(interventions) {
    // Init tooltip element
    initTooltip();

    // Load saved diagram or use default
    const saved = storage.getDiagram();
    if (saved && saved.graphData && Array.isArray(saved.graphData.nodes)) {
        currentGraphData = saved.graphData;
    } else {
        currentGraphData = structuredClone(DEFAULT_GRAPH_DATA);
    }

    // Initialize all graph containers
    GRAPH_CONFIGS.forEach(config => {
        const container = document.getElementById(config.containerId);
        if (container) {
            renderGraph(config);
        }
    });
}

// ═══════════════════════════════════════════════════════════
// TOOLTIP
// ═══════════════════════════════════════════════════════════

function initTooltip() {
    if (tooltipEl) return;
    tooltipEl = document.createElement('div');
    tooltipEl.className = 'cy-tooltip';
    tooltipEl.style.display = 'none';
    document.body.appendChild(tooltipEl);
}

function applyNeighborhoodHighlight(cy, node) {
    cy.batch(() => {
        cy.elements().addClass('hover-dimmed');
        cy.nodes('[styleClass="groupLabel"]').removeClass('hover-dimmed');

        // Tier 0: the clicked/hovered node
        node.removeClass('hover-dimmed').addClass('hover-highlight');

        // Tier 1: direct edges + neighbors
        const t1Edges = node.connectedEdges();
        t1Edges.removeClass('hover-dimmed').addClass('hover-highlight');
        const t1Nodes = t1Edges.connectedNodes().not(node);
        t1Nodes.removeClass('hover-dimmed').addClass('hover-neighbor');

        // Tier 2: edges + neighbors one step further out
        t1Nodes.forEach(n => {
            const t2Edges = n.connectedEdges().not(t1Edges);
            t2Edges.removeClass('hover-dimmed').addClass('hover-highlight-2');
            const t2Nodes = t2Edges.connectedNodes().not(node).not(t1Nodes);
            t2Nodes.removeClass('hover-dimmed').addClass('hover-neighbor-2');
        });
    });
}

function attachTooltipHandlers(cy, container) {
    cy.on('mouseover', 'node', (event) => {
        const node = event.target;
        const sc = node.data('styleClass');

        // Skip hover entirely when a regular node is pinned
        if (pinnedNode) return;

        // Show tooltip
        const tooltip = node.data('tooltip');
        if (tooltip) {
            showTooltip(event, container, buildNodeTooltipHtml(node.data('label'), tooltip));
        }

        // Neighborhood highlight (skip for interventions when tx mode is active, and for labels)
        if (sc === 'groupLabel') return;
        if (sc === 'intervention' && showInterventions) return;

        applyNeighborhoodHighlight(cy, node);
    });

    cy.on('mouseover', 'edge', (event) => {
        const edge = event.target;
        const tooltipText = edge.data('tooltip');
        if (!tooltipText) return;
        showTooltip(event, container, buildEdgeTooltipHtml(
            edge.data('source'), edge.data('target'), tooltipText, edge.data('label')
        ));
    });

    cy.on('mouseout', 'node, edge', () => {
        hideTooltip();
        if (pinnedNode) return;  // Don't clear highlighting when pinned
        cy.batch(() => {
            cy.elements().removeClass('hover-dimmed hover-highlight hover-neighbor hover-neighbor-2 hover-highlight-2');
        });
    });

    // Click-to-pin for regular nodes
    cy.on('tap', 'node', (evt) => {
        const node = evt.target;
        const sc = node.data('styleClass');
        if (sc === 'groupLabel') return;
        if (sc === 'intervention') return;  // Handled by intervention system

        const id = node.id();

        if (pinnedNode === id) {
            // Unpin — clear highlight
            pinnedNode = null;
            hideTooltip();
            cy.remove(cy.edges('.dormant-edge'));
            cy.batch(() => {
                cy.elements().removeClass('hover-dimmed hover-highlight hover-neighbor hover-neighbor-2 hover-highlight-2');
            });
        } else {
            // Pin this node — apply highlight
            pinnedNode = id;
            hideTooltip();
            // Remove any previous dormant edges, then add relevant ones
            cy.remove(cy.edges('.dormant-edge'));
            const dIds = cy.scratch('dormantIds');
            const dEdges = cy.scratch('dormantEdges');
            if (dIds && dEdges) {
                // Only add edges whose source AND target nodes exist in the graph
                const canAdd = (e) => cy.getElementById(e.data.source).nonempty() && cy.getElementById(e.data.target).nonempty();
                const addEdges = (edges) => {
                    const valid = edges.filter(canAdd);
                    if (valid.length) cy.add(valid.map(e => ({ group: 'edges', data: { ...e.data }, classes: 'dormant-edge' })));
                };
                // Round 1: edges connected to the pinned node
                const round1 = dEdges.filter(e => e.data.source === id || e.data.target === id);
                addEdges(round1);
                // Collect tier-1 neighbor IDs (including through just-added edges)
                const t1NodeIds = new Set();
                node.connectedEdges().connectedNodes().not(node).forEach(n => t1NodeIds.add(n.id()));
                // Round 2: edges of tier-1 neighbors
                const round1Set = new Set(round1);
                const round2 = dEdges.filter(e =>
                    !round1Set.has(e) &&
                    (t1NodeIds.has(e.data.source) || t1NodeIds.has(e.data.target))
                );
                addEdges(round2);
            }
            applyNeighborhoodHighlight(cy, node);
        }

        // Filter check-in panel when in interventions mode
        if (showInterventions) {
            if (_checkinFilterNodeId === id) {
                _checkinFilterNodeId = null;
            } else {
                _checkinFilterNodeId = id;
            }
            buildCheckinPanel(currentGraphData);
        }
    });

    // Click empty canvas to unpin
    cy.on('tap', (evt) => {
        if (evt.target === cy && pinnedNode) {
            pinnedNode = null;
            cy.remove(cy.edges('.dormant-edge'));
            cy.batch(() => {
                cy.elements().removeClass('hover-dimmed hover-highlight hover-neighbor hover-neighbor-2 hover-highlight-2');
            });
            if (showInterventions && _checkinFilterNodeId) {
                _checkinFilterNodeId = null;
                buildCheckinPanel(currentGraphData);
            }
        }
    });

    cy.on('pan zoom', () => {
        hideTooltip();
    });
}

function showTooltip(event, container, html) {
    if (!tooltipEl) initTooltip();
    tooltipEl.innerHTML = html;
    tooltipEl.style.display = 'block';

    const rect = container.getBoundingClientRect();
    let x = rect.left + event.renderedPosition.x + 12;
    let y = rect.top + event.renderedPosition.y - 12;

    // Measure after content is set
    const tw = tooltipEl.offsetWidth;
    const th = tooltipEl.offsetHeight;

    // Clamp to viewport
    if (x + tw > window.innerWidth - 8) x = window.innerWidth - tw - 8;
    if (y + th > window.innerHeight - 8) y = window.innerHeight - th - 8;
    if (x < 8) x = 8;
    if (y < 8) y = 8;

    tooltipEl.style.left = x + 'px';
    tooltipEl.style.top = y + 'px';
}

function hideTooltip() {
    if (tooltipEl) tooltipEl.style.display = 'none';
}

function buildNodeTooltipHtml(label, tooltip) {
    const cleanLabel = (label || '').split('\n')[0];
    let html = `<div class="cy-tooltip-title">${escapeHtml(cleanLabel)}</div>`;
    if (tooltip.evidence) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Evidence:</span> ${escapeHtml(tooltip.evidence)}</div>`;
    }
    if (tooltip.stat) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Stat:</span> ${escapeHtml(tooltip.stat)}</div>`;
    }
    if (tooltip.citation) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Citation:</span> ${escapeHtml(tooltip.citation)}</div>`;
    }
    if (tooltip.mechanism) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Mechanism:</span> ${escapeHtml(tooltip.mechanism)}</div>`;
    }
    return html;
}

function buildEdgeTooltipHtml(source, target, tooltipText, label) {
    let html = `<div class="cy-tooltip-title">${escapeHtml(source)} → ${escapeHtml(target)}</div>`;
    if (label) {
        html += `<div class="cy-tooltip-row"><span class="cy-tooltip-label">Stat:</span> ${escapeHtml(label)}</div>`;
    }
    html += `<div class="cy-tooltip-row">${escapeHtml(tooltipText)}</div>`;
    return html;
}

// ═══════════════════════════════════════════════════════════
// LEGEND
// ═══════════════════════════════════════════════════════════

function addLegend(container, interventionsVisible) {
    // Place legend outside graph canvas, in the parent container
    const parent = container.parentElement;
    const existing = parent.querySelector('.graph-legend');
    if (existing) existing.remove();

    const legend = document.createElement('div');
    legend.className = 'graph-legend';
    legend.innerHTML = `
        <div class="legend-section">
            <div class="legend-row"><span class="legend-swatch" style="background:#1b4332;border:2px solid #081c15"></span> Robust</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#b45309;border:2px solid #78350f"></span> Moderate</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#6b21a8;border:2px solid #4c1d95"></span> Preliminary</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#1e3a5f;border:2px solid #0f172a"></span> Symptom</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px solid #1f2937"></span> Mechanism</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#065f46;border:2px solid #047857;border-style:dashed"></span> Intervention</div>
        </div>
        <div class="legend-section">
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px solid #1f2937;opacity:1"></span> Confirmed</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px dashed #1f2937;opacity:0.4"></span> Unconfirmed</div>
            <div class="legend-row"><span class="legend-swatch" style="background:#374151;border:2px dashed #1f2937;opacity:0.2"></span> Inactive</div>
        </div>
        <div class="legend-section">
            <div class="legend-row"><span class="legend-line" style="background:#b45309"></span> Source-colored</div>
            <div class="legend-row"><span class="legend-line legend-line-dashed" style="border-color:#6b21a8"></span> Dashed (prelim)</div>
            <div class="legend-row"><span class="legend-line legend-line-dashed" style="border-color:#ef4444"></span> Feedback (red)</div>
            <div class="legend-row"><span class="legend-line legend-line-dashed" style="border-color:#3b82f6"></span> Protective (blue)</div>
        </div>
        ${interventionsVisible ? '<div class="legend-section"><div class="legend-hint">Sidebar: hover to highlight, click to pin &middot; Badges: click for details</div></div>' : ''}
    `;

    parent.appendChild(legend);
}

// ═══════════════════════════════════════════════════════════
// CYTOSCAPE INSTANCE MANAGEMENT
// ═══════════════════════════════════════════════════════════

function createCyInstance(containerId, graphData) {
    const container = document.getElementById(containerId);
    if (!container) return null;

    // Destroy previous instance
    destroyCyInstance(containerId);

    // Always exclude intervention nodes from the graph (shown via sidebar instead)
    const interventionIds = new Set();
    const filteredNodes = graphData.nodes.filter(n => {
        if (n.data.styleClass === 'intervention') {
            interventionIds.add(n.data.id);
            return false; // Never render intervention nodes on graph
        }
        return true;
    });

    // Build set of unconfirmed/inactive/external node IDs whose edges (and nodes) are hidden by default
    const dormantIds = new Set(
        graphData.nodes
            .filter(n => n.data.confirmed === 'no' || n.data.confirmed === 'inactive' || n.data.confirmed === 'external')
            .map(n => n.data.id)
    );
    const dormantEdges = graphData.edges.filter(e =>
        dormantIds.has(e.data.source) || dormantIds.has(e.data.target)
    );

    // Filter edges: always exclude intervention edges, plus feedback/protective/dormant toggles
    const filteredEdges = graphData.edges.filter(e => {
        if (interventionIds.has(e.data.source) || interventionIds.has(e.data.target)) {
            return false;
        }
        if (!showFeedbackEdges && e.data.edgeType === 'feedback') {
            return false;
        }
        if (!showProtectiveEdges && e.data.edgeType === 'protective') {
            return false;
        }
        if (dormantIds.has(e.data.source) || dormantIds.has(e.data.target)) {
            return false;
        }
        return true;
    });

    // Build Cytoscape elements (clean mechanism graph, no intervention nodes)
    const elements = [
        ...filteredNodes.map(n => ({ group: 'nodes', data: { ...n.data } })),
        ...filteredEdges.map(e => ({ group: 'edges', data: { ...e.data } })),
        // Inject tier label nodes
        ...Object.entries(TIER_LABELS).map(([tier, label]) => ({
            group: 'nodes',
            data: { id: `_tier_${tier}`, label, styleClass: 'groupLabel', tier: parseInt(tier) },
        })),
    ];

    const cy = window.cytoscape({
        container: container,
        elements: elements,
        style: CYTOSCAPE_STYLES,
        userZoomingEnabled: false,
        userPanningEnabled: false,  // Disabled: page scroll handles vertical movement
        boxSelectionEnabled: false,
        selectionType: 'single',
        minZoom: 0.1,
        maxZoom: 10,
    });

    cyInstances.set(containerId, cy);
    cy.scratch('dormantIds', dormantIds);
    cy.scratch('dormantEdges', dormantEdges);

    // Build check-in panel BEFORE layout so the sidebar is populated
    // and the grid container has its final width for layout calculations
    if (containerId === 'causal-graph-cy') {
        buildCheckinPanel(graphData);
    }

    // Layout: tiered columns
    runTieredLayout(cy, container);

    // Attach custom wheel handler, zoom controls, tooltips, legend
    attachWheelHandler(container, cy);
    addZoomControls(container, cy);
    attachTooltipHandlers(cy, container);
    addLegend(container, showInterventions);

    // If interventions mode is active, show sidebar + badges
    if (showInterventions) {
        const maps = buildInterventionMaps(graphData);
        cy.scratch('interventionMaps', maps);
        addInterventionBadges(container, cy, maps);
    }

    // If defense mode is active, apply heatmap + defense badges + shield badges
    if (showDefenseMode) {
        applyDefenseHeatmap(cy, graphData);
        addDefenseBadges(container, cy, graphData);
        addShieldBadges(container, cy, graphData);
    }

    return cy;
}

function destroyCyInstance(containerId) {
    const cy = cyInstances.get(containerId);
    if (cy) {
        cy.destroy();
        cyInstances.delete(containerId);
    }
    // Clean up threat edge marching ants interval
    if (_threatEdgeInterval) {
        clearInterval(_threatEdgeInterval);
        _threatEdgeInterval = null;
    }
    const container = document.getElementById(containerId);
    if (container) {
        if (container._wheelHandler) {
            container.removeEventListener('wheel', container._wheelHandler);
            container._wheelHandler = null;
        }
        const controls = container.querySelector('.panzoom-controls');
        if (controls) controls.remove();
        const sidebar = container.querySelector('.tx-sidebar');
        if (sidebar) sidebar.remove();
        removeInterventionBadges(container);
        removeDefenseBadges(container);
        removeShieldBadges(container);
        const popover = container.querySelector('.tx-popover');
        if (popover) popover.remove();
        const legend = container.parentElement?.querySelector('.graph-legend');
        if (legend) legend.remove();
    }
}

// ═══════════════════════════════════════════════════════════
// TIERED COLUMN LAYOUT (preset positions)
// ═══════════════════════════════════════════════════════════

// Column assignment for every non-intervention node (1-10, left to right)

function computeTieredPositions(cy, width, height) {
    const padX = 60;
    const padY = 80;
    const labelWidth = 55;

    // Row position helper: maps tier 1..10 (inc. half-steps) to y-coordinate
    function rowY(tier) {
        return padY + ((tier - 1) / (NUM_TIERS - 1)) * (height - 2 * padY);
    }

    // Group non-intervention, non-label nodes by tier
    const tierBuckets = {};
    for (let t = 1; t <= NUM_TIERS; t++) tierBuckets[t] = [];
    const interventionNodes = [];

    cy.nodes().forEach(n => {
        const sc = n.data('styleClass');
        if (sc === 'groupLabel') return;
        if (sc === 'intervention') {
            interventionNodes.push(n);
            return;
        }
        const tier = NODE_TIERS[n.id()];
        if (tier !== undefined) {
            tierBuckets[tier].push(n.id());
        }
    });

    const positions = {};

    // Place mechanism/evidence nodes in their row (spread horizontally)
    for (let t = 1; t <= NUM_TIERS; t++) {
        const ids = tierBuckets[t];
        if (ids.length === 0) continue;

        const y = rowY(t);
        const usableW = width - 2 * padX - labelWidth;
        const startX = padX + labelWidth;

        ids.forEach((id, i) => {
            const x = ids.length > 1
                ? startX + i * usableW / (ids.length - 1)
                : startX + usableW / 2;
            positions[id] = { x, y };
        });
    }

    // Place intervention nodes at half-tier row positions
    const interventionRowBuckets = {};
    interventionNodes.forEach(n => {
        const id = n.id();
        let col = INTERVENTION_COLUMNS[id];

        if (col === undefined) {
            // Fallback: compute from target tiers
            const targets = n.outgoers('edge').targets();
            const tiers = targets.map(t => NODE_TIERS[t.id()]).filter(t => t !== undefined);
            if (tiers.length === 0) {
                col = 0.5;
            } else {
                const minT = Math.min(...tiers);
                col = minT + 0.5;
                col = Math.max(0.5, Math.min(NUM_TIERS - 0.5, col));
            }
        }

        if (!interventionRowBuckets[col]) interventionRowBuckets[col] = [];
        interventionRowBuckets[col].push(n);
    });

    // Position interventions within each row, aligned to primary target X
    const minGap = 45;
    Object.entries(interventionRowBuckets).forEach(([row, nodes]) => {
        const y = rowY(parseFloat(row));

        // Collect desired X for each intervention (from primary target's position)
        const entries = nodes.map(n => {
            const targets = n.outgoers('edge').targets();
            let targetX = null;
            for (let i = 0; i < targets.length; i++) {
                const tPos = positions[targets[i].id()];
                if (tPos) { targetX = tPos.x; break; }
            }
            return { id: n.id(), x: targetX || (padX + labelWidth + (width - 2 * padX - labelWidth) / 2) };
        });

        // Sort by X for consistent stacking
        entries.sort((a, b) => a.x - b.x);

        // Enforce minimum horizontal gap to prevent overlap
        for (let i = 1; i < entries.length; i++) {
            if (entries[i].x - entries[i - 1].x < minGap) {
                entries[i].x = entries[i - 1].x + minGap;
            }
        }

        entries.forEach(entry => {
            positions[entry.id] = { x: entry.x, y };
        });
    });

    // Place tier label nodes at the far left margin of each row
    for (let t = 1; t <= NUM_TIERS; t++) {
        positions[`_tier_${t}`] = { x: 18, y: rowY(t) };
    }

    return positions;
}

function runTieredLayout(cy, container) {
    const isFullscreen = container.classList.contains('fullscreen');
    const w = container.offsetWidth || 900;

    if (isFullscreen) {
        // Fullscreen: fit everything into the viewport
        const h = container.offsetHeight || 500;
        const positions = computeTieredPositions(cy, w, h);
        cy.layout({
            name: 'preset',
            positions: (node) => positions[node.id()] || undefined,
            fit: false,
            animate: false,
        }).run();
        cy.fit(cy.elements(), 40);
        return;
    }

    // Portrait scroll mode: compute positions at an ideal height, then size
    // the container to match so the page scroll reveals the graph naturally.
    const idealH = 80 + (NUM_TIERS - 1) * 160 + 80; // ~1600px
    const positions = computeTieredPositions(cy, w, idealH);
    cy.layout({
        name: 'preset',
        positions: (node) => positions[node.id()] || undefined,
        fit: false,
        animate: false,
    }).run();

    // Measure actual bounding box and zoom to fit container width
    const bb = cy.elements().boundingBox();
    const PAD = 40;
    const zoomForWidth = (w - 2 * PAD) / bb.w;

    // Set container height to the scaled graph height
    const scaledHeight = bb.h * zoomForWidth + 2 * PAD;
    container.style.height = scaledHeight + 'px';
    cy.resize();

    // Apply zoom and position: fill width, align to top
    cy.zoom(zoomForWidth);
    cy.pan({
        x: -bb.x1 * zoomForWidth + PAD,
        y: -bb.y1 * zoomForWidth + PAD,
    });
}

// ═══════════════════════════════════════════════════════════
// CUSTOM WHEEL HANDLER (trackpad pan / shift+zoom)
// ═══════════════════════════════════════════════════════════

function attachWheelHandler(container, cy) {
    // In portrait scroll mode, do NOT intercept wheel events — let the page scroll naturally.
    // The fullscreen wheel handler is attached separately by enterFullscreen().
    if (container._wheelHandler) {
        container.removeEventListener('wheel', container._wheelHandler);
        container._wheelHandler = null;
    }
}

function attachWheelHandlerForFullscreen(container, cy) {
    if (container._wheelHandler) {
        container.removeEventListener('wheel', container._wheelHandler);
    }

    const handler = (e) => {
        e.preventDefault();

        if (e.shiftKey) {
            // Shift + scroll = zoom toward cursor
            const zoomFactor = e.deltaY > 0 ? 0.9 : 1.1;
            const currentZoom = cy.zoom();
            const newZoom = Math.max(0.1, Math.min(10, currentZoom * zoomFactor));
            const rect = container.getBoundingClientRect();
            cy.zoom({
                level: newZoom,
                renderedPosition: {
                    x: e.clientX - rect.left,
                    y: e.clientY - rect.top
                }
            });
        } else {
            // Normal scroll = pan
            cy.panBy({ x: -e.deltaX, y: -e.deltaY });
        }
    };

    container.addEventListener('wheel', handler, { passive: false });
    container._wheelHandler = handler;
}

// ═══════════════════════════════════════════════════════════
// ZOOM CONTROLS
// ═══════════════════════════════════════════════════════════

function addZoomControls(container, cy) {
    const existing = container.querySelector('.panzoom-controls');
    if (existing) existing.remove();

    const controls = document.createElement('div');
    controls.className = 'panzoom-controls';
    controls.innerHTML = `
        <button class="panzoom-btn" title="Zoom in" data-action="zoomIn">+</button>
        <button class="panzoom-btn" title="Zoom out" data-action="zoomOut">&minus;</button>
        <button class="panzoom-btn" title="Fit to view" data-action="fit">&#x21BA;</button>
        <button class="panzoom-btn" title="Fullscreen" data-action="fullscreen">&#x26F6;</button>
        <button class="panzoom-btn panzoom-btn-toggle ${showInterventions ? 'active' : ''}" title="${showInterventions ? 'Hide interventions' : 'Show interventions'}" data-action="toggleTx">Tx</button>
        <button class="panzoom-btn panzoom-btn-toggle panzoom-btn-defense ${showDefenseMode ? 'active' : ''}" title="${showDefenseMode ? 'Hide defense heatmap' : 'Show defense heatmap'}" data-action="toggleDf">Df</button>
        <button class="panzoom-btn panzoom-btn-toggle panzoom-btn-fb ${showFeedbackEdges ? 'active' : ''}" title="${showFeedbackEdges ? 'Hide feedback loops' : 'Show feedback loops'}" data-action="toggleFb">Fb</button>
        <button class="panzoom-btn panzoom-btn-toggle panzoom-btn-protective ${showProtectiveEdges ? 'active' : ''}" title="${showProtectiveEdges ? 'Hide protective mechanisms' : 'Show protective mechanisms'}" data-action="toggleProtective">Pr</button>
    `;

    const center = () => ({ x: container.offsetWidth / 2, y: container.offsetHeight / 2 });

    controls.querySelector('[data-action="zoomIn"]').addEventListener('click', () => {
        cy.zoom({ level: cy.zoom() * 1.5, renderedPosition: center() });
    });
    controls.querySelector('[data-action="zoomOut"]').addEventListener('click', () => {
        cy.zoom({ level: cy.zoom() * 0.67, renderedPosition: center() });
    });
    controls.querySelector('[data-action="fit"]').addEventListener('click', () => {
        cy.fit(undefined, 30);
    });
    controls.querySelector('[data-action="fullscreen"]').addEventListener('click', () => {
        toggleFullscreen(container, cy);
    });
    controls.querySelector('[data-action="toggleTx"]').addEventListener('click', () => {
        toggleInterventions();
    });
    controls.querySelector('[data-action="toggleDf"]').addEventListener('click', () => {
        toggleDefenseMode();
    });
    controls.querySelector('[data-action="toggleFb"]').addEventListener('click', () => {
        toggleFeedbackEdges();
    });
    controls.querySelector('[data-action="toggleProtective"]').addEventListener('click', () => {
        toggleProtectiveEdges();
    });

    controls.addEventListener('mousedown', (e) => e.stopPropagation());
    controls.addEventListener('touchstart', (e) => e.stopPropagation());

    container.appendChild(controls);
}

// ═══════════════════════════════════════════════════════════
// INTERVENTION SIDEBAR + BADGE + POPOVER SYSTEM
// ═══════════════════════════════════════════════════════════


function buildInterventionSidebar(container, cy, maps) {
    const existing = container.querySelector('.tx-sidebar');
    if (existing) existing.remove();

    const sidebar = document.createElement('div');
    sidebar.className = 'tx-sidebar';

    let html = '<div class="tx-sidebar-header">Interventions</div>';
    INTERVENTION_CATEGORIES.forEach(cat => {
        html += '<div class="tx-sidebar-category">';
        html += `<div class="tx-sidebar-cat-header">${cat.name}</div>`;
        cat.items.forEach(id => {
            const node = maps.interventionNodeMap.get(id);
            if (!node) return;
            const label = node.label.replace(/\n/g, ' ');
            const evidence = node.tooltip?.evidence || '';
            const pinned = pinnedInterventions.has(id);
            html += `<div class="tx-sidebar-item${pinned ? ' pinned' : ''}" data-tx-id="${id}">`;
            html += `<span class="tx-sidebar-item-label">${label}</span>`;
            html += `<span class="tx-sidebar-item-evidence">${evidence}</span>`;
            html += '</div>';
        });
        html += '</div>';
    });

    sidebar.innerHTML = html;

    sidebar.querySelectorAll('.tx-sidebar-item').forEach(item => {
        const txId = item.dataset.txId;

        item.addEventListener('mouseenter', () => {
            highlightInterventionTargets(cy, txId, maps);
        });
        item.addEventListener('mouseleave', () => {
            restoreFromSidebarHighlight(cy, maps);
        });
        item.addEventListener('click', () => {
            if (pinnedInterventions.has(txId)) {
                pinnedInterventions.delete(txId);
                item.classList.remove('pinned');
            } else {
                pinnedInterventions.add(txId);
                item.classList.add('pinned');
            }
            restoreFromSidebarHighlight(cy, maps);
        });
    });

    sidebar.addEventListener('mousedown', e => e.stopPropagation());
    sidebar.addEventListener('touchstart', e => e.stopPropagation());
    sidebar.addEventListener('wheel', e => e.stopPropagation());

    container.appendChild(sidebar);
}

function highlightInterventionTargets(cy, txId, maps) {
    const targets = maps.interventionTargets.get(txId) || [];
    const targetIds = new Set(targets.map(t => t.target));

    // Also include pinned intervention targets
    pinnedInterventions.forEach(pinnedId => {
        const pts = maps.interventionTargets.get(pinnedId) || [];
        pts.forEach(t => targetIds.add(t.target));
    });

    cy.batch(() => {
        cy.elements().addClass('tx-deep-dimmed').removeClass('tx-dimmed tx-highlighted tx-target-highlighted');
        cy.nodes('[styleClass="groupLabel"]').removeClass('tx-deep-dimmed');

        targetIds.forEach(tId => {
            const node = cy.getElementById(tId);
            if (node.length) node.removeClass('tx-deep-dimmed').addClass('tx-target-highlighted');
        });

        // Show edges between highlighted targets for context
        cy.edges().forEach(e => {
            if (targetIds.has(e.data('source')) && targetIds.has(e.data('target'))) {
                e.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
            }
        });
    });
}

function restoreFromSidebarHighlight(cy, maps) {
    cy.batch(() => {
        cy.elements().removeClass('tx-deep-dimmed tx-dimmed tx-highlighted tx-target-highlighted');

        if (pinnedInterventions.size > 0) {
            cy.elements().addClass('tx-deep-dimmed');
            cy.nodes('[styleClass="groupLabel"]').removeClass('tx-deep-dimmed');

            const highlightedIds = new Set();
            pinnedInterventions.forEach(pinnedId => {
                const targets = maps.interventionTargets.get(pinnedId) || [];
                targets.forEach(t => {
                    const node = cy.getElementById(t.target);
                    if (node.length) {
                        node.removeClass('tx-deep-dimmed').addClass('tx-target-highlighted');
                        highlightedIds.add(t.target);
                    }
                });
            });

            cy.edges().forEach(e => {
                if (highlightedIds.has(e.data('source')) && highlightedIds.has(e.data('target'))) {
                    e.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
                }
            });
        }
    });
}

function addInterventionBadges(container, cy, maps) {
    removeInterventionBadges(container);

    const overlay = document.createElement('div');
    overlay.className = 'tx-badge-overlay';
    container.appendChild(overlay);

    function updatePositions() {
        overlay.innerHTML = '';
        maps.targetInterventions.forEach((txIds, nodeId) => {
            const node = cy.getElementById(nodeId);
            if (!node.length || node.removed()) return;
            const bb = node.renderedBoundingBox();

            const badge = document.createElement('div');
            badge.className = 'tx-badge';
            badge.textContent = txIds.length;
            badge.dataset.nodeId = nodeId;
            badge.style.left = `${bb.x2 - 2}px`;
            badge.style.top = `${bb.y1 - 2}px`;

            badge.addEventListener('click', e => {
                e.stopPropagation();
                showNodePopover(container, cy, nodeId, maps);
                // Filter check-in panel to this node's interventions
                if (_checkinFilterNodeId === nodeId) {
                    _checkinFilterNodeId = null;
                } else {
                    _checkinFilterNodeId = nodeId;
                }
                buildCheckinPanel(currentGraphData);
            });

            overlay.appendChild(badge);
        });
    }

    updatePositions();
    cy.on('pan zoom', updatePositions);
    cy.one('layoutstop', updatePositions);
    container._badgeHandler = updatePositions;
}

function removeInterventionBadges(container) {
    const overlay = container.querySelector('.tx-badge-overlay');
    if (overlay) overlay.remove();

    const cy = cyInstances.get(container.id);
    if (cy && container._badgeHandler) {
        cy.off('pan zoom', container._badgeHandler);
        container._badgeHandler = null;
    }
}

function showNodePopover(container, cy, nodeId, maps) {
    const existing = container.querySelector('.tx-popover');
    if (existing) {
        if (existing.dataset.nodeId === nodeId) { existing.remove(); return; }
        existing.remove();
    }

    const txIds = maps.targetInterventions.get(nodeId) || [];
    if (txIds.length === 0) return;

    const node = cy.getElementById(nodeId);
    if (!node.length) return;

    const bb = node.renderedBoundingBox();
    const popover = document.createElement('div');
    popover.className = 'tx-popover';
    popover.dataset.nodeId = nodeId;
    popover.style.left = `${(bb.x1 + bb.x2) / 2}px`;
    popover.style.top = `${bb.y2 + 8}px`;

    const nodeLabel = node.data('label').split('\n')[0];
    let html = `<div class="tx-popover-header">${txIds.length} intervention${txIds.length > 1 ? 's' : ''} targeting ${nodeLabel}</div>`;
    txIds.forEach(txId => {
        const txNode = maps.interventionNodeMap.get(txId);
        if (!txNode) return;
        const label = txNode.label.replace(/\n/g, ' ');
        const pinned = pinnedInterventions.has(txId);
        html += `<div class="tx-popover-item${pinned ? ' pinned' : ''}" data-tx-id="${txId}">${label}</div>`;
    });
    popover.innerHTML = html;

    popover.querySelectorAll('.tx-popover-item').forEach(item => {
        const txId = item.dataset.txId;
        item.addEventListener('click', e => {
            e.stopPropagation();
            if (pinnedInterventions.has(txId)) {
                pinnedInterventions.delete(txId);
                item.classList.remove('pinned');
            } else {
                pinnedInterventions.add(txId);
                item.classList.add('pinned');
            }
            const sidebarItem = container.querySelector(`.tx-sidebar-item[data-tx-id="${txId}"]`);
            if (sidebarItem) sidebarItem.classList.toggle('pinned', pinnedInterventions.has(txId));
            restoreFromSidebarHighlight(cy, maps);
        });
        item.addEventListener('mouseenter', () => {
            highlightInterventionTargets(cy, txId, maps);
        });
        item.addEventListener('mouseleave', () => {
            restoreFromSidebarHighlight(cy, maps);
        });
    });

    popover.addEventListener('mousedown', e => e.stopPropagation());
    container.appendChild(popover);

    const closeHandler = e => {
        if (!popover.contains(e.target) && !e.target.classList.contains('tx-badge')) {
            popover.remove();
            document.removeEventListener('click', closeHandler);
        }
    };
    setTimeout(() => document.addEventListener('click', closeHandler), 100);
}

// ═══════════════════════════════════════════════════════════
// DEFENSE MODE: CHECK-IN PANEL + HEATMAP ENGINE
// ═══════════════════════════════════════════════════════════


function todayKey() {
    return new Date().toISOString().split('T')[0];
}

function dateOffsetKey(offset) {
    const d = new Date();
    d.setDate(d.getDate() + offset);
    return d.toISOString().split('T')[0];
}

function formatDateLabel(key) {
    const today = todayKey();
    if (key === today) return 'Today';
    const yesterday = dateOffsetKey(-1);
    if (key === yesterday) return 'Yesterday';
    const d = new Date(key + 'T12:00:00');
    return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

function parseOptionalNumber(raw, { min = -Infinity, max = Infinity, integer = false } = {}) {
    if (raw === null || raw === undefined) return undefined;
    const text = String(raw).trim();
    if (!text) return undefined;
    const parsed = Number(text);
    if (!Number.isFinite(parsed)) return undefined;
    const clamped = Math.max(min, Math.min(max, parsed));
    return integer ? Math.round(clamped) : clamped;
}

function escapeHtmlAttr(value) {
    return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
}

function habitStatusLabel(status) {
    switch (status) {
        case 'helpful': return 'Helpful';
        case 'neutral': return 'Neutral';
        case 'harmful': return 'Harmful';
        default: return 'Unknown';
    }
}

function normalizeMorningSlider(value) {
    const parsed = parseOptionalNumber(value, { min: 0, max: 10, integer: true });
    if (parsed === undefined) {
        return { hasValue: false, sliderValue: 5, displayValue: 'Not set' };
    }
    return { hasValue: true, sliderValue: parsed, displayValue: String(parsed) };
}

function buildMorningSliderField({ field, label, hint, value }) {
    const normalized = normalizeMorningSlider(value);
    return `<label class="defense-protocol-slider-field">
        <div class="defense-protocol-slider-head">
            <span class="defense-protocol-slider-label">${label}</span>
            <span class="defense-protocol-slider-value" data-value-for="${field}">${normalized.displayValue}</span>
        </div>
        <span class="defense-protocol-slider-hint">${hint}</span>
        <input data-field="${field}" data-has-value="${normalized.hasValue ? '1' : '0'}" data-touched="0" type="range" min="0" max="10" step="1" value="${escapeHtmlAttr(normalized.sliderValue)}">
    </label>`;
}

// ── Check-in Panel ──

let checkinDateOffset = 0; // 0 = today, -1 = yesterday, etc.

let _activeCheckinTxId = null; // currently expanded/highlighted intervention

// ── Activity Feed (right column) ──
function buildActivityCardHtml(entry) {
    let html = `<div class="activity-card" data-tx-id="${entry.txId}">`;
    html += `<div class="activity-card-header">`;
    html += `<span class="activity-card-label">${entry.label}</span>`;
    html += `<span class="activity-card-time">${entry.timeAgo}</span>`;
    html += `</div>`;
    entry.changes.forEach(c => {
        const sign = c.diff > 0 ? '+' : '';
        const diffPct = sign + Math.round(c.diff * 100) + '%';
        const color = c.diff > 0 ? '#22c55e' : '#ef4444';
        html += `<div class="activity-card-row">`;
        html += `<span class="activity-card-diff" style="color:${color}">${diffPct}</span>`;
        html += `<span class="activity-card-node">${c.nodeLabel}</span>`;
        html += `<span class="activity-card-score">${Math.round(c.after * 100)}%</span>`;
        html += `</div>`;
    });
    html += `</div>`;
    return html;
}

function buildRealityFeedbackHtml({
    dateKey,
    nightOutcome = {},
    morningState = {},
    habitStatusCounts = {},
} = {}) {
    const objectiveRateValue = nightOutcome.microArousalRatePerHour ?? '';
    const objectiveCountValue = nightOutcome.microArousalCount ?? '';
    const objectiveConfidenceValue = nightOutcome.confidence ?? '';
    const objectiveSourceValue = typeof nightOutcome.source === 'string' ? nightOutcome.source : '';
    const morningGlobalValue = morningState.globalSensation ?? '';
    const morningNeckValue = morningState.neckTightness ?? '';
    const morningJawValue = morningState.jawSoreness ?? '';
    const morningEarValue = morningState.earFullness ?? '';
    const morningAnxietyValue = morningState.healthAnxiety ?? '';

    let html = '';
    html += `<div class="defense-protocol-card">`;
    html += `<div class="defense-protocol-title">Reality Feedback (for ${formatDateLabel(dateKey)})</div>`;
    html += `<div class="defense-protocol-hint">One-variable rule: change one habit at a time for cleaner evidence.</div>`;
    html += `<div class="defense-protocol-section-title">Objective (night)</div>`;
    html += `<div class="defense-protocol-grid">`;
    html += `<label class="defense-protocol-field"><span>Micro/hr</span><input data-field="micro-rate" type="number" step="0.1" min="0" placeholder="e.g. 3.4" value="${escapeHtmlAttr(objectiveRateValue)}"></label>`;
    html += `<label class="defense-protocol-field"><span>Micro count</span><input data-field="micro-count" type="number" step="1" min="0" placeholder="e.g. 24" value="${escapeHtmlAttr(objectiveCountValue)}"></label>`;
    html += `<label class="defense-protocol-field"><span>Confidence (0-1)</span><input data-field="micro-confidence" type="number" step="0.01" min="0" max="1" placeholder="e.g. 0.92" value="${escapeHtmlAttr(objectiveConfidenceValue)}"></label>`;
    html += `<label class="defense-protocol-field"><span>Source</span><input data-field="micro-source" type="text" placeholder="muse / oura / manual" value="${escapeHtmlAttr(objectiveSourceValue)}"></label>`;
    html += `</div>`;
    html += `<div class="defense-protocol-section-title">Morning state (0-10)</div>`;
    html += `<div class="defense-protocol-guidance">`;
    html += `<div class="defense-protocol-guidance-title">Quick scoring rule</div>`;
    html += `<ul class="defense-protocol-guidance-list">`;
    html += `<li>Score once within 30 min of waking.</li>`;
    html += `<li>Use fixed anchors daily: 0 none, 5 moderate, 10 worst plausible.</li>`;
    html += `<li>Use whole numbers for what you feel now.</li>`;
    html += `</ul>`;
    html += `</div>`;
    html += `<div class="defense-protocol-slider-grid">`;
    html += buildMorningSliderField({
        field: 'morning-global',
        label: 'Global',
        hint: 'Overall alarm / unwell load',
        value: morningGlobalValue,
    });
    html += buildMorningSliderField({
        field: 'morning-neck',
        label: 'Neck',
        hint: 'Tightness / stiffness / spasm load',
        value: morningNeckValue,
    });
    html += buildMorningSliderField({
        field: 'morning-jaw',
        label: 'Jaw',
        hint: 'Ache / clench fatigue',
        value: morningJawValue,
    });
    html += buildMorningSliderField({
        field: 'morning-ear',
        label: 'Ear',
        hint: 'Fullness / pressure',
        value: morningEarValue,
    });
    html += buildMorningSliderField({
        field: 'morning-anxiety',
        label: 'Anxiety',
        hint: 'Health-threat feeling on waking',
        value: morningAnxietyValue,
    });
    html += `</div>`;
    html += `<div class="defense-protocol-actions">`;
    html += `<button class="defense-protocol-btn" data-action="save-protocol">Save + Recompute</button>`;
    html += `<button class="defense-protocol-btn subtle" data-action="recompute-only">Recompute only</button>`;
    html += `</div>`;
    html += `<div class="defense-protocol-summary">`;
    html += `<span class="defense-protocol-chip helpful">${habitStatusCounts.helpful || 0} helpful</span>`;
    html += `<span class="defense-protocol-chip neutral">${habitStatusCounts.neutral || 0} neutral</span>`;
    html += `<span class="defense-protocol-chip harmful">${habitStatusCounts.harmful || 0} harmful</span>`;
    html += `<span class="defense-protocol-chip unknown">${habitStatusCounts.unknown || 0} unknown</span>`;
    html += `</div>`;
    html += `</div>`;
    return html;
}

function wireRealityFeedbackHandlers(host, { dateKey, graphData }) {
    const morningSliderInputs = host.querySelectorAll('.defense-protocol-slider-grid input[type="range"][data-field]');
    morningSliderInputs.forEach((slider) => {
        const valueChip = host.querySelector(`[data-value-for="${slider.dataset.field}"]`);
        const syncSlider = () => {
            slider.dataset.touched = '1';
            if (valueChip) valueChip.textContent = slider.value;
        };
        slider.addEventListener('input', syncSlider);
        slider.addEventListener('change', syncSlider);
    });

    const readMorningSlider = (field) => {
        const slider = host.querySelector(`[data-field="${field}"]`);
        if (!slider) return undefined;
        const touched = slider.dataset.touched === '1';
        const hasValue = slider.dataset.hasValue === '1';
        if (!touched && !hasValue) return undefined;
        return parseOptionalNumber(slider.value, { min: 0, max: 10, integer: true });
    };

    const saveProtocolBtn = host.querySelector('[data-action="save-protocol"]');
    if (saveProtocolBtn) {
        saveProtocolBtn.addEventListener('click', () => {
            const microRate = parseOptionalNumber(host.querySelector('[data-field="micro-rate"]')?.value, { min: 0 });
            const microCount = parseOptionalNumber(host.querySelector('[data-field="micro-count"]')?.value, { min: 0, integer: true });
            const microConfidence = parseOptionalNumber(host.querySelector('[data-field="micro-confidence"]')?.value, { min: 0, max: 1 });
            const source = (host.querySelector('[data-field="micro-source"]')?.value || '').trim();

            const globalSensation = readMorningSlider('morning-global');
            const neckTightness = readMorningSlider('morning-neck');
            const jawSoreness = readMorningSlider('morning-jaw');
            const earFullness = readMorningSlider('morning-ear');
            const healthAnxiety = readMorningSlider('morning-anxiety');

            const hasOutcomeData = (
                microRate !== undefined ||
                microCount !== undefined ||
                microConfidence !== undefined ||
                source.length > 0
            );
            if (hasOutcomeData) {
                storage.upsertNightOutcome({
                    nightId: dateKey,
                    microArousalRatePerHour: microRate,
                    microArousalCount: microCount,
                    confidence: microConfidence,
                    source: source || undefined,
                });
            }

            const hasMorningData = (
                globalSensation !== undefined ||
                neckTightness !== undefined ||
                jawSoreness !== undefined ||
                earFullness !== undefined ||
                healthAnxiety !== undefined
            );
            if (hasMorningData) {
                storage.upsertMorningState({
                    nightId: dateKey,
                    globalSensation,
                    neckTightness,
                    jawSoreness,
                    earFullness,
                    healthAnxiety,
                });
            }

            const classifications = storage.recomputeHabitClassifications();
            const harmful = classifications.filter(c => c.status === 'harmful').length;
            const helpful = classifications.filter(c => c.status === 'helpful').length;
            showToastNotification(
                `Saved ${formatDateLabel(dateKey)} · ${helpful} helpful / ${harmful} harmful`,
                '',
                { duration: 2200 }
            );
            buildCheckinPanel(graphData);
            if (showDefenseMode) reRenderGraphs();
        });
    }

    const recomputeOnlyBtn = host.querySelector('[data-action="recompute-only"]');
    if (recomputeOnlyBtn) {
        recomputeOnlyBtn.addEventListener('click', () => {
            const classifications = storage.recomputeHabitClassifications();
            showToastNotification(`Recomputed ${classifications.length} habit statuses`, '', { duration: 1800 });
            buildCheckinPanel(graphData);
            if (showDefenseMode) reRenderGraphs();
        });
    }
}

function ensureActivityLayout(panel) {
    let feedbackHost = panel.querySelector('.reality-feedback-host');
    let feedList = panel.querySelector('.activity-feed-list');
    if (!feedbackHost || !feedList) {
        panel.innerHTML = '<div class="reality-feedback-host"></div><div class="activity-feed-list"></div>';
        feedbackHost = panel.querySelector('.reality-feedback-host');
        feedList = panel.querySelector('.activity-feed-list');
    }
    return { feedbackHost, feedList };
}

function renderActivityFeed({
    graphData,
    dateKey = todayKey(),
    nightOutcome = {},
    morningState = {},
    habitStatusCounts = {},
} = {}) {
    const panel = document.getElementById('activity-feed-panel');
    if (!panel) return;
    const { feedbackHost, feedList } = ensureActivityLayout(panel);

    feedbackHost.innerHTML = buildRealityFeedbackHtml({
        dateKey,
        nightOutcome,
        morningState,
        habitStatusCounts,
    });
    if (graphData) {
        wireRealityFeedbackHandlers(feedbackHost, { dateKey, graphData });
    }

    // Skip full rebuild if panel already has cards (incremental updates handle it)
    if (feedList.querySelector('.activity-card') && _activityFeed.length > 0) return;

    if (_activityFeed.length === 0) {
        feedList.innerHTML = `<div class="activity-feed-header">Activity</div>
            <div class="activity-feed-empty">Check off defenses to see score changes</div>`;
        return;
    }

    // Full rebuild (called on initial render only)
    let html = `<div class="activity-feed-header">Activity <span class="activity-feed-count">${_activityFeed.length}</span></div>`;
    _activityFeed.forEach(entry => { html += buildActivityCardHtml(entry); });
    feedList.innerHTML = html;
}

// Incremental insert: prepend a single new card without re-rendering existing ones
function insertActivityCard(entry) {
    const panel = document.getElementById('activity-feed-panel');
    if (!panel) return;
    const { feedList } = ensureActivityLayout(panel);

    // Ensure header exists and remove empty placeholder
    let header = feedList.querySelector('.activity-feed-header');
    const empty = feedList.querySelector('.activity-feed-empty');
    if (empty) empty.remove();
    if (!header) {
        header = document.createElement('div');
        header.className = 'activity-feed-header';
        feedList.prepend(header);
    }
    header.innerHTML = `Activity <span class="activity-feed-count">${_activityFeed.length}</span>`;

    // Insert new card right after the header
    const temp = document.createElement('div');
    temp.innerHTML = buildActivityCardHtml(entry);
    const card = temp.firstElementChild;
    header.insertAdjacentElement('afterend', card);
}

// Incremental remove: remove a single card by txId without re-rendering
function removeActivityCard(txId) {
    const panel = document.getElementById('activity-feed-panel');
    if (!panel) return;
    const { feedList } = ensureActivityLayout(panel);

    const card = feedList.querySelector(`.activity-card[data-tx-id="${txId}"]`);
    if (card) card.remove();

    // Update count badge
    const header = feedList.querySelector('.activity-feed-header');
    if (header) {
        if (_activityFeed.length === 0) {
            feedList.innerHTML = `<div class="activity-feed-header">Activity</div>
                <div class="activity-feed-empty">Check off defenses to see score changes</div>`;
        } else {
            header.innerHTML = `Activity <span class="activity-feed-count">${_activityFeed.length}</span>`;
        }
    }
}

function buildCheckinPanel(graphData) {
    const panel = document.getElementById('defense-checkin');
    if (!panel) return;

    const maps = buildInterventionMaps(graphData);
    const impact = computeNetworkImpact(graphData);
    const dateKey = dateOffsetKey(checkinDateOffset);
    const checkIns = storage.getCheckIns(dateKey);
    const checkInSet = new Set(checkIns);
    const nightOutcome = storage.getNightOutcome(dateKey) || {};
    const morningState = storage.getMorningState(dateKey) || {};
    const habitClassifications = storage.getHabitClassifications();
    const habitClassMap = new Map();
    const habitStatusCounts = {
        helpful: 0,
        neutral: 0,
        harmful: 0,
        unknown: 0,
    };
    habitClassifications.forEach(record => {
        if (!record || !record.interventionId) return;
        const status = record.status || 'unknown';
        habitClassMap.set(record.interventionId, record);
        if (habitStatusCounts[status] !== undefined) {
            habitStatusCounts[status] += 1;
        } else {
            habitStatusCounts.unknown += 1;
        }
    });

    // Compute streaks for all interventions
    const rangeData = storage.getCheckInsRange(7);
    function streak(id) {
        let count = 0;
        Object.values(rangeData).forEach(ids => { if (ids.includes(id)) count++; });
        return count;
    }

    // Build reverse lookup: intervention id → category name
    const catLookup = new Map();
    INTERVENTION_CATEGORIES.forEach(cat => {
        cat.items.forEach(id => catLookup.set(id, cat.name));
    });

    function quantile(sortedVals, q) {
        if (!sortedVals || sortedVals.length === 0) return 0;
        if (q <= 0) return sortedVals[0];
        if (q >= 1) return sortedVals[sortedVals.length - 1];
        const idx = (sortedVals.length - 1) * q;
        const lo = Math.floor(idx);
        const hi = Math.ceil(idx);
        if (lo === hi) return sortedVals[lo];
        return sortedVals[lo] + (sortedVals[hi] - sortedVals[lo]) * (idx - lo);
    }

    // Sort all interventions by impact score descending
    const allTxIds = [...maps.interventionNodeMap.keys()];
    allTxIds.sort((a, b) => {
        const sa = (impact.get(a) || { score: 0 }).score;
        const sb = (impact.get(b) || { score: 0 }).score;
        return sb - sa;
    });

    const allImpactScoresAsc = allTxIds
        .map(id => (impact.get(id) || { score: 0 }).score)
        .sort((a, b) => a - b);
    const impactMedThreshold = quantile(allImpactScoresAsc, 1 / 3);
    const impactHighThreshold = quantile(allImpactScoresAsc, 2 / 3);

    // Filter out hidden interventions
    const hiddenSet = new Set(storage.getHiddenInterventions());
    const visibleTxIds = allTxIds.filter(id => !hiddenSet.has(id));
    const hiddenTxIds = allTxIds.filter(id => hiddenSet.has(id));

    // Apply node filter when in interventions mode
    let filteredTxIds = visibleTxIds;
    let filterNodeLabel = null;
    if (showInterventions && _checkinFilterNodeId) {
        const targetTxIds = new Set(maps.targetInterventions.get(_checkinFilterNodeId) || []);
        filteredTxIds = visibleTxIds.filter(id => targetTxIds.has(id));
        const filterNode = graphData.nodes.find(n => n.data.id === _checkinFilterNodeId);
        filterNodeLabel = filterNode ? filterNode.data.label.split('\n')[0] : _checkinFilterNodeId;
    }

    const maxScore = allTxIds.length > 0
        ? (impact.get(allTxIds[0]) || { score: 1 }).score
        : 1;

    // ── Category Synergy Computation ──
    const activeCats = new Set();
    INTERVENTION_CATEGORIES.forEach(cat => {
        if (cat.items.some(id => checkInSet.has(id))) {
            activeCats.add(cat.name);
        }
    });
    const totalCats = INTERVENTION_CATEGORIES.length;
    const synergyMultiplier = activeCats.size <= 1
        ? 1.0
        : 1 + 0.5 * ((activeCats.size - 1) / (totalCats - 1));

    // ── Shield Rating Computation ──
    const defenseScores = computeDefenseScores(graphData);
    let weightedSum = 0;
    let weightTotal = 0;
    defenseScores.forEach((entry, nodeId) => {
        const tier = NODE_TIERS[nodeId];
        if (tier === undefined) return;
        const w = tier >= 8 ? 3 : tier >= 6 ? 2 : 1;
        weightedSum += entry.score * w;
        weightTotal += w;
    });
    const rawRating = weightTotal > 0 ? (weightedSum / weightTotal) * 100 : 0;
    const shieldRating = Math.min(100, Math.round(rawRating * synergyMultiplier));
    const shieldTier = getShieldTier(shieldRating);

    // Level-up toast detection
    if (_prevShieldTier !== null && _prevShieldTier !== shieldTier.label) {
        showToastNotification(`Level Up! \u2192 ${shieldTier.label}`, 'toast-level-up');
    }
    _prevShieldTier = shieldTier.label;

    // Helper: render a single intervention item
    function renderItem(id, dimmed) {
        const node = maps.interventionNodeMap.get(id);
        if (!node) return '';
        const label = node.label.replace(/\n/g, ' ');
        const s = streak(id);
        const checked = checkInSet.has(id);
        const cat = catLookup.get(id) || '';
        const habitStatus = habitClassMap.get(id)?.status || 'unknown';
        const habitStatusText = habitStatusLabel(habitStatus);
        const score = (impact.get(id) || { score: 0 }).score;
        const barPct = maxScore > 0 ? Math.round((score / maxScore) * 100) : 0;
        const isActive = _activeCheckinTxId === id;
        const scoreClass = score >= impactHighThreshold
            ? 'high'
            : score >= impactMedThreshold
                ? 'med'
                : 'low';
        const dimClass = dimmed ? ' defense-item-hidden' : '';

        // Streak tier class
        let streakClass;
        if (s >= 7) streakClass = 'fortified';
        else if (s >= 5) streakClass = 'strong';
        else if (s >= 3) streakClass = 'med';
        else streakClass = 'low';
        const streakLabel = s >= 7 ? `7/7 \u2605` : `${s}/7`;

        let h = `<div class="defense-item-wrapper${dimClass}">`;
        h += `<div class="defense-checkin-item${checked ? ' checked' : ''}${isActive ? ' active' : ''}" data-tx-id="${id}">`;
        h += `<div class="defense-check-btn">`;
        h += `<input type="checkbox" data-tx-id="${id}" ${checked ? 'checked' : ''}>`;
        h += `<span class="defense-check-mark"></span>`;
        h += `</div>`;
        h += `<div class="defense-item-content">`;
        h += `<span class="defense-item-label">${label}</span>`;
        h += `<div class="defense-item-meta">`;
        h += `<span class="defense-item-cat">${cat}</span>`;
        h += `<span class="defense-habit-status ${habitStatus}" title="Personal status: ${habitStatusText}">${habitStatusText}</span>`;
        h += `<span class="defense-impact-bar-wrap"><span class="defense-impact-bar" style="width:${barPct}%"></span></span>`;
        h += `<span class="defense-item-score ${scoreClass}"></span>`;
        h += `<span class="defense-item-streak ${streakClass}">${streakLabel}</span>`;
        h += `</div>`;
        h += `</div>`;
        h += `</div>`;

        // Inline evidence detail (shown on hover via popover)
        const tooltip = node.tooltip || {};
        const targets = maps.interventionTargets.get(id) || [];
        h += `<div class="defense-item-detail">`;
        if (tooltip.mechanism) {
            h += `<div class="defense-item-detail-row">`;
            h += `<span class="defense-item-detail-value">${tooltip.mechanism}</span>`;
            h += `</div>`;
        }
        if (tooltip.evidence) {
            h += `<div class="defense-item-detail-row">`;
            h += `<span class="defense-item-detail-label">Evidence:</span>`;
            h += `<span class="defense-item-detail-value">${tooltip.evidence}</span>`;
            h += `</div>`;
        }
        if (tooltip.stat) {
            h += `<div class="defense-item-detail-row">`;
            h += `<span class="defense-item-detail-label">Stat:</span>`;
            h += `<span class="defense-item-detail-value">${tooltip.stat}</span>`;
            h += `</div>`;
        }
        if (tooltip.citation) {
            h += `<div class="defense-item-detail-row">`;
            h += `<span class="defense-item-detail-label">Citation:</span>`;
            h += `<span class="defense-item-detail-value">${tooltip.citation}</span>`;
            h += `</div>`;
        }
        if (targets.length > 0) {
            h += `<div class="defense-item-detail-targets">`;
            targets.forEach(t => {
                const targetNode = graphData.nodes.find(n => n.data.id === t.target);
                const targetLabel = targetNode ? targetNode.data.label.split('\n')[0] : t.target;
                h += `<span class="defense-item-target-tag">${targetLabel}</span>`;
            });
            h += `</div>`;
        }
        h += `</div>`;
        h += `</div>`; // close defense-item-wrapper
        return h;
    }

    const checkedFiltered = filteredTxIds.filter(id => checkInSet.has(id)).length;

    // ── Build Header HTML ──
    let html = '';
    html += `<div class="defense-sidebar-header">`;
    html += `<div class="defense-sidebar-title">Daily Defense Check-in</div>`;

    // Shield Rating Ring
    const circumference = 2 * Math.PI * 27; // r=27
    const dashLen = (shieldRating / 100) * circumference;
    html += `<div class="shield-rating-container">`;
    html += `<div class="shield-ring-wrap">`;
    html += `<svg class="shield-ring-svg" viewBox="0 0 64 64">`;
    html += `<circle class="shield-ring-bg" cx="32" cy="32" r="27"/>`;
    html += `<circle class="shield-ring-fill" cx="32" cy="32" r="27" stroke="${shieldTier.color}" stroke-dasharray="${dashLen} ${circumference}"/>`;
    html += `</svg>`;
    html += `<span class="shield-ring-value">${shieldRating}</span>`;
    html += `</div>`;
    html += `<div class="shield-rating-info">`;
    html += `<span class="shield-tier-label ${shieldTier.css}">${shieldTier.label}</span>`;
    html += `<span class="shield-active-count">${checkedFiltered}/${filteredTxIds.length} active today</span>`;
    html += `</div>`;
    html += `</div>`;

    if (filterNodeLabel) {
        html += `<div class="defense-sidebar-filter">Filtering: ${filterNodeLabel} <span class="defense-filter-clear" data-action="clear-filter">&times;</span></div>`;
    }
    html += `<div class="defense-sidebar-nav">`;
    html += `<button class="defense-date-btn" data-dir="-1">&larr;</button>`;
    html += `<span class="defense-date-label">${formatDateLabel(dateKey)}</span>`;
    html += `<button class="defense-date-btn" data-dir="1" ${checkinDateOffset >= 0 ? 'disabled' : ''}>&rarr;</button>`;
    html += `</div>`;
    html += `</div>`; // close defense-sidebar-header

    filteredTxIds.forEach(id => { html += renderItem(id, false); });

    // "Show N hidden" toggle
    if (hiddenTxIds.length > 0) {
        html += `<div class="defense-hidden-toggle" data-action="toggle-hidden">Show ${hiddenTxIds.length} hidden</div>`;
        html += `<div class="defense-hidden-section" style="display:none;">`;
        hiddenTxIds.forEach(id => { html += renderItem(id, true); });
        html += `</div>`;
    }

    panel.innerHTML = html;

    // ── Wire Event Handlers ──

    // Wire clear filter button
    const clearFilterBtn = panel.querySelector('.defense-filter-clear');
    if (clearFilterBtn) {
        clearFilterBtn.addEventListener('click', () => {
            _checkinFilterNodeId = null;
            buildCheckinPanel(graphData);
        });
    }

    // Wire checkbox handlers — stop propagation so row click doesn't fire
    panel.querySelectorAll('.defense-check-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
        });
    });
    panel.querySelectorAll('input[type="checkbox"]').forEach(cb => {
        cb.addEventListener('change', () => {
            const txId = cb.dataset.txId;
            const wasChecked = cb.checked;
            // Flash animation on the row
            const row = cb.closest('.defense-checkin-item');
            if (row && wasChecked) {
                row.classList.add('flash');
                setTimeout(() => row.classList.remove('flash'), 300);
            }
            // Snapshot defense scores before toggle
            const scoresBefore = computeDefenseScores(graphData);
            storage.toggleCheckIn(dateKey, txId);
            storage.upsertNightExposure({
                nightId: dateKey,
                interventionId: txId,
                enabled: cb.checked,
                tags: ['daily_checkin'],
            });
            storage.recomputeHabitClassifications();
            // Snapshot defense scores after toggle
            const scoresAfter = computeDefenseScores(graphData);
            if (wasChecked) {
                // Checked on: compute score diff and add feed entry
                const changes = [];
                scoresAfter.forEach(({ score: after }, nodeId) => {
                    const before = scoresBefore.get(nodeId);
                    if (!before) return;
                    const diff = after - before.score;
                    if (Math.abs(diff) >= 0.005) {
                        const n = graphData.nodes.find(n => n.data.id === nodeId);
                        const nodeLabel = n ? n.data.label.split('\n')[0] : nodeId;
                        changes.push({ nodeLabel, diff, after });
                    }
                });
                if (changes.length > 0) {
                    changes.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
                    const txNode = maps.interventionNodeMap.get(txId);
                    const txLabel = txNode ? txNode.label.replace(/\n/g, ' ') : txId;
                    const entry = {
                        txId,
                        label: '+ ' + txLabel,
                        timeAgo: 'just now',
                        changes,
                    };
                    _activityFeed.unshift(entry);
                    insertActivityCard(entry);
                }
            } else {
                // Unchecked: remove the feed entry for this txId
                for (let i = 0; i < _activityFeed.length; i++) {
                    if (_activityFeed[i].txId === txId) {
                        _activityFeed.splice(i, 1);
                        break;
                    }
                }
                removeActivityCard(txId);
            }
            // Scroll to the intervention's target node on graph
            scrollToInterventionTargets(txId, maps, graphData);
            // Delay rebuild slightly so flash is visible
            setTimeout(() => {
                buildCheckinPanel(graphData);
                if (showDefenseMode) reRenderGraphs();
            }, wasChecked ? 150 : 0);
        });
    });

    // Wire row click → scroll to target node + highlight + show detail
    panel.querySelectorAll('.defense-checkin-item').forEach(row => {
        row.addEventListener('click', (e) => {
            // Don't trigger if clicking the checkbox area
            if (e.target.closest('.defense-check-btn')) return;

            const txId = row.dataset.txId;

            // Toggle active state
            if (_activeCheckinTxId === txId) {
                _activeCheckinTxId = null;
                clearCheckinHighlight();
            } else {
                _activeCheckinTxId = txId;
                scrollToInterventionTargets(txId, maps, graphData);
            }
            buildCheckinPanel(graphData);
        });
    });

    // Wire date navigation
    panel.querySelectorAll('.defense-date-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const dir = parseInt(btn.dataset.dir);
            checkinDateOffset += dir;
            if (checkinDateOffset > 0) checkinDateOffset = 0;
            buildCheckinPanel(graphData);
        });
    });

    // Wire hover popover for evidence detail
    let popover = document.getElementById('defense-detail-popover');
    if (!popover) {
        popover = document.createElement('div');
        popover.id = 'defense-detail-popover';
        document.body.appendChild(popover);
        popover.addEventListener('mouseenter', () => {
            clearTimeout(popover._hideTimeout);
        });
        popover.addEventListener('mouseleave', () => {
            popover.style.display = 'none';
        });
    }
    popover.style.display = 'none';

    panel.querySelectorAll('.defense-item-wrapper').forEach(wrapper => {
        wrapper.addEventListener('mouseenter', () => {
            clearTimeout(popover._hideTimeout);
            const detail = wrapper.querySelector('.defense-item-detail');
            if (!detail || !detail.innerHTML.trim()) return;
            popover.innerHTML = detail.innerHTML;
            const rect = wrapper.getBoundingClientRect();
            popover.style.top = rect.top + 'px';
            popover.style.left = (rect.right + 8) + 'px';
            popover.style.display = 'block';
            // Clamp if overflowing viewport bottom
            const popRect = popover.getBoundingClientRect();
            if (popRect.bottom > window.innerHeight - 10) {
                popover.style.top = Math.max(10, window.innerHeight - popRect.height - 10) + 'px';
            }
        });
        wrapper.addEventListener('mouseleave', () => {
            popover._hideTimeout = setTimeout(() => {
                popover.style.display = 'none';
            }, 150);
        });
    });

    // Wire "Show N hidden" toggle
    const hiddenToggle = panel.querySelector('.defense-hidden-toggle');
    const hiddenSection = panel.querySelector('.defense-hidden-section');
    if (hiddenToggle && hiddenSection) {
        hiddenToggle.addEventListener('click', () => {
            const isShown = hiddenSection.style.display !== 'none';
            hiddenSection.style.display = isShown ? 'none' : 'block';
            hiddenToggle.textContent = isShown
                ? `Show ${hiddenTxIds.length} hidden`
                : `Hide ${hiddenTxIds.length} hidden`;
        });
    }

    // Right-click context menu for hide/unhide
    let ctxMenu = document.getElementById('defense-context-menu');
    if (!ctxMenu) {
        ctxMenu = document.createElement('div');
        ctxMenu.id = 'defense-context-menu';
        ctxMenu.innerHTML = `<div class="defense-context-option"></div>`;
        document.body.appendChild(ctxMenu);
    }
    ctxMenu.style.display = 'none';

    function dismissCtxMenu() { ctxMenu.style.display = 'none'; }

    panel.querySelectorAll('.defense-checkin-item').forEach(row => {
        row.addEventListener('contextmenu', (e) => {
            e.preventDefault();
            const txId = row.dataset.txId;
            const isHidden = hiddenSet.has(txId);
            const option = ctxMenu.querySelector('.defense-context-option');
            option.textContent = isHidden ? 'Unhide' : 'Hide from list';
            ctxMenu.style.left = e.clientX + 'px';
            ctxMenu.style.top = e.clientY + 'px';
            ctxMenu.style.display = 'block';

            // Wire click (replace handler each time)
            option.onclick = () => {
                storage.toggleHiddenIntervention(txId);
                dismissCtxMenu();
                buildCheckinPanel(graphData);
            };
        });
    });

    // Dismiss context menu on click-outside or scroll
    document.addEventListener('click', dismissCtxMenu, { once: true });
    panel.addEventListener('scroll', dismissCtxMenu, { once: true });

    // Render the activity feed in the right column
    renderActivityFeed({
        graphData,
        dateKey,
        nightOutcome,
        morningState,
        habitStatusCounts,
    });
}

function scrollToInterventionTargets(txId, maps, graphData) {
    const cy = cyInstances.get('causal-graph-cy');
    if (!cy) return;

    const targets = maps.interventionTargets.get(txId) || [];
    const targetIds = new Set(targets.map(t => t.target));
    if (targetIds.size === 0) return;

    // Collect target nodes in Cytoscape
    const targetNodes = cy.collection();
    targetIds.forEach(tId => {
        const node = cy.getElementById(tId);
        if (node.length) targetNodes.merge(node);
    });
    if (targetNodes.empty()) return;

    // Highlight: dim everything, then highlight targets and their connecting edges
    cy.batch(() => {
        cy.elements().addClass('tx-deep-dimmed').removeClass('tx-dimmed tx-highlighted tx-target-highlighted');
        cy.nodes('[styleClass="groupLabel"]').removeClass('tx-deep-dimmed');

        targetNodes.removeClass('tx-deep-dimmed').addClass('tx-target-highlighted');

        // Also highlight edges between targets for context
        cy.edges().forEach(e => {
            if (targetIds.has(e.data('source')) && targetIds.has(e.data('target'))) {
                e.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
            }
            // Highlight edges FROM targets (downstream)
            if (targetIds.has(e.data('source'))) {
                e.removeClass('tx-deep-dimmed').addClass('tx-highlighted');
                const tgtNode = cy.getElementById(e.data('target'));
                if (tgtNode.length) tgtNode.removeClass('tx-deep-dimmed');
            }
        });
    });

    // Scroll the first target node into view
    const primary = targetNodes.first();
    const bb = primary.renderedBoundingBox();
    const container = document.getElementById('causal-graph-cy');
    if (!container) return;

    const containerRect = container.getBoundingClientRect();
    const nodeCenterY = containerRect.top + (bb.y1 + bb.y2) / 2 + window.scrollY;
    const viewportMid = window.innerHeight / 2;

    window.scrollTo({
        top: Math.max(0, nodeCenterY - viewportMid),
        behavior: 'smooth',
    });
}

function clearCheckinHighlight() {
    const cy = cyInstances.get('causal-graph-cy');
    if (!cy) return;
    cy.batch(() => {
        cy.elements().removeClass('tx-deep-dimmed tx-dimmed tx-highlighted tx-target-highlighted');
    });
}

// ── Heatmap Application ──

function applyDefenseHeatmap(cy, graphData) {
    const scores = computeDefenseScores(graphData);

    // Track threat edges with direction info for marching ants
    const forwardThreatIds = [];
    const feedbackThreatIds = [];

    cy.batch(() => {
        cy.nodes().forEach(node => {
            const sc = node.data('styleClass');
            if (sc === 'groupLabel') return;
            const entry = scores.get(node.id());
            if (!entry) return;

            const { color, border, opacity } = scoreToColor(entry.score, entry.isDirect);
            node.data('defenseColor', border);
            node.data('defenseBg', color);
            node.data('defenseOpacity', opacity);
            node.data('defenseScore', entry.score);
            node.addClass('defense-node');

            // Semantic defense state classes with underlay glow
            node.removeClass('defense-fortified defense-contested defense-exposed');
            if (entry.score >= 0.6) {
                node.addClass('defense-fortified');
            } else if (entry.score >= 0.3) {
                node.addClass('defense-contested');
            } else {
                node.addClass('defense-exposed');
            }
        });

        // Edge coloring: based on how defended the source and target are
        cy.edges().forEach(edge => {
            const srcEntry = scores.get(edge.data('source'));
            const tgtEntry = scores.get(edge.data('target'));
            if (!srcEntry && !tgtEntry) return;

            // Edge defense = min of source and target (weakest link)
            const edgeScore = Math.min(
                srcEntry ? srcEntry.score : 0,
                tgtEntry ? tgtEntry.score : 0
            );
            const { color } = scoreToColor(edgeScore, false);
            // Undefended edges stay prominent; defended edges fade
            const edgeWidth = edgeScore > 0.5 ? 0.8 : (edgeScore > 0.2 ? 1.2 : 2.0);
            const edgeOp = edgeScore > 0.5 ? 0.35 : (edgeScore > 0.2 ? 0.55 : 0.85);

            edge.data('defenseColor', color);
            edge.data('defenseWidth', edgeWidth);
            edge.data('defenseOpacity', edgeOp);
            edge.addClass('defense-edge');

            // Track threat edges for marching ants (separate by direction)
            if (edgeScore < 0.2) {
                if (edge.data('edgeType') === 'feedback') {
                    feedbackThreatIds.push(edge.id());
                } else {
                    forwardThreatIds.push(edge.id());
                }
            }
        });
    });

    // Marching ants animation on threat edges
    // Forward edges: ants march upward (against causal flow)
    // Feedback edges: ants march upward (along edge direction, which goes up)
    if (_threatEdgeInterval) {
        clearInterval(_threatEdgeInterval);
        _threatEdgeInterval = null;
    }
    const allThreatIds = [...forwardThreatIds, ...feedbackThreatIds];
    if (allThreatIds.length > 0) {
        let fwdOffset = 0;
        let fbOffset = 0;
        _threatEdgeInterval = setInterval(() => {
            // Decrement moves ants target→source (upward for forward edges)
            fwdOffset = (fwdOffset - 0.4 + 10) % 10;
            // Increment moves ants source→target (upward for feedback edges)
            fbOffset = (fbOffset + 0.4) % 10;
            cy.batch(() => {
                forwardThreatIds.forEach(edgeId => {
                    const edge = cy.getElementById(edgeId);
                    if (edge.nonempty()) {
                        edge.style({
                            'line-style': 'dashed',
                            'line-dash-pattern': [6, 4],
                            'line-dash-offset': fwdOffset,
                        });
                    }
                });
                feedbackThreatIds.forEach(edgeId => {
                    const edge = cy.getElementById(edgeId);
                    if (edge.nonempty()) {
                        edge.style({
                            'line-style': 'dashed',
                            'line-dash-pattern': [6, 4],
                            'line-dash-offset': fbOffset,
                        });
                    }
                });
            });
        }, 50);
    }
}

function addDefenseBadges(container, cy, graphData) {
    removeDefenseBadges(container);
    if (!tooltipEl) initTooltip();
    const scores = computeDefenseScores(graphData);

    // Pre-compute per-node intervention breakdown for hover popover
    const maps = buildInterventionMaps(graphData);
    const rangeData = storage.getCheckInsRange(7);
    const ratings = storage.getAllRatings();
    const ratingMap = {};
    ratings.forEach(r => { ratingMap[r.interventionId] = r.effectiveness; });

    function interventionStrengthDetail(txId) {
        const eff = ratingMap[txId] || 'untested';
        const weight = EFFECTIVENESS_WEIGHTS[eff] || 0.5;
        let daysActive = 0;
        Object.values(rangeData).forEach(ids => { if (ids.includes(txId)) daysActive++; });
        const strength = weight * (daysActive / 7);
        return { eff, weight, daysActive, strength };
    }

    // Node label helper
    function nodeLabel(id) {
        const n = graphData.nodes.find(n => n.data.id === id);
        return n ? n.data.label.split('\n')[0] : id;
    }

    // Build direct breakdown: nodeId → [{ label, eff, daysActive, strength }]
    const directBreakdowns = new Map();
    maps.targetInterventions.forEach((txIds, nodeId) => {
        const items = txIds.map(txId => {
            const txNode = maps.interventionNodeMap.get(txId);
            const label = txNode ? txNode.label.replace(/\n/g, ' ') : txId;
            const detail = interventionStrengthDetail(txId);
            return { label, ...detail };
        });
        items.sort((a, b) => b.strength - a.strength);
        directBreakdowns.set(nodeId, items);
    });

    // Build adjacency (same as computeDefenseScores)
    const adjacency = new Map();
    graphData.edges.forEach(e => {
        const src = e.data.source;
        const tgt = e.data.target;
        if (e.data.edgeType === 'feedback' || e.data.edgeType === 'protective') return;
        if (maps.interventionNodeMap.has(src)) return;
        if (!adjacency.has(src)) adjacency.set(src, []);
        adjacency.get(src).push(tgt);
    });

    // BFS to track cascade contributions: nodeId → [{ sourceNodeId, contribution, hops }]
    const cascadeContribs = new Map();
    graphData.nodes.forEach(n => {
        if (n.data.styleClass !== 'intervention') cascadeContribs.set(n.data.id, []);
    });

    // Compute direct scores (mirroring computeDefenseScores)
    const directScores = new Map();
    maps.targetInterventions.forEach((txIds, nId) => {
        let total = 0;
        txIds.forEach(txId => { total += interventionStrengthDetail(txId).strength; });
        directScores.set(nId, Math.min(1, total));
    });

    const queue = [];
    directScores.forEach((score, nId) => {
        if (score > 0) queue.push({ nodeId: nId, strength: score, depth: 0, sourceNodeId: nId });
    });
    const visited = new Set();
    while (queue.length > 0) {
        const { nodeId: nId, strength, depth, sourceNodeId } = queue.shift();
        const children = adjacency.get(nId) || [];
        children.forEach(childId => {
            const cascaded = strength * CASCADE_DECAY;
            if (cascaded < 0.01) return;
            const contribs = cascadeContribs.get(childId);
            if (!contribs) return;
            // Record this cascade contribution
            const existing = contribs.find(c => c.sourceNodeId === sourceNodeId);
            if (existing) {
                if (cascaded > existing.contribution) {
                    existing.contribution = cascaded;
                    existing.hops = depth + 1;
                }
            } else {
                contribs.push({ sourceNodeId, contribution: cascaded, hops: depth + 1 });
            }
            const key = `${childId}-${sourceNodeId}-${depth}`;
            if (!visited.has(key)) {
                visited.add(key);
                queue.push({ nodeId: childId, strength: cascaded, depth: depth + 1, sourceNodeId });
            }
        });
    }

    const overlay = document.createElement('div');
    overlay.className = 'defense-badge-overlay';
    container.appendChild(overlay);

    function updatePositions() {
        overlay.innerHTML = '';
        scores.forEach((entry, nodeId) => {
            if (entry.score === 0 && !entry.isDirect) return;
            const node = cy.getElementById(nodeId);
            if (!node.length || node.removed()) return;
            const sc = node.data('styleClass');
            if (sc === 'groupLabel') return;

            const bb = node.renderedBoundingBox();
            const { color } = scoreToColor(entry.score, entry.isDirect);
            const pct = scoreToLabel(entry.score);

            const badge = document.createElement('div');
            badge.className = 'defense-badge';
            badge.textContent = pct;
            badge.style.left = `${bb.x2 - 2}px`;
            badge.style.top = `${bb.y1 - 2}px`;
            badge.style.background = color;
            badge.style.borderColor = color;
            badge.style.pointerEvents = 'auto';
            badge.style.cursor = 'default';

            const nLabel = node.data('label').split('\n')[0];
            badge.addEventListener('mouseenter', () => {
                let html = `<div class="cy-tooltip-title">${pct} — ${nLabel}</div>`;

                // Direct interventions
                const directItems = directBreakdowns.get(nodeId);
                if (directItems && directItems.length > 0) {
                    html += `<div style="margin-bottom:4px;color:#9ca3af;font-size:11px;">Direct:</div>`;
                    directItems.forEach(it => {
                        const pctStr = Math.round(it.strength * 100) + '%';
                        const effLabel = it.eff.replace('_', ' ');
                        html += `<div class="cy-tooltip-row" style="display:flex;justify-content:space-between;gap:8px;">`;
                        html += `<span>${it.label}</span>`;
                        html += `<span style="color:#9ca3af;white-space:nowrap;">${it.daysActive}/7d · ${effLabel} · ${pctStr}</span>`;
                        html += `</div>`;
                    });
                }

                // Cascade contributions
                const contribs = (cascadeContribs.get(nodeId) || [])
                    .filter(c => c.contribution >= 0.01)
                    .sort((a, b) => b.contribution - a.contribution);
                if (contribs.length > 0) {
                    if (directItems && directItems.length > 0) {
                        html += `<div style="margin-top:6px;margin-bottom:4px;color:#9ca3af;font-size:11px;">Cascaded:</div>`;
                    }
                    contribs.forEach(c => {
                        const srcLabel = nodeLabel(c.sourceNodeId);
                        const cPct = Math.round(c.contribution * 100) + '%';
                        // Show which interventions defend the source node
                        const srcItems = directBreakdowns.get(c.sourceNodeId) || [];
                        const txNames = srcItems.map(it => it.label).join(', ');
                        html += `<div class="cy-tooltip-row" style="margin-bottom:3px;">`;
                        html += `<div style="display:flex;justify-content:space-between;gap:8px;">`;
                        html += `<span>via ${srcLabel}</span>`;
                        html += `<span style="color:#9ca3af;white-space:nowrap;">${c.hops} hop${c.hops > 1 ? 's' : ''} · ${cPct}</span>`;
                        html += `</div>`;
                        if (txNames) {
                            html += `<div style="color:#6b7280;font-size:10px;margin-top:1px;">${txNames}</div>`;
                        }
                        html += `</div>`;
                    });
                }

                tooltipEl.innerHTML = html;
                tooltipEl.style.display = 'block';
                const r = badge.getBoundingClientRect();
                tooltipEl.style.left = (r.right + 8) + 'px';
                tooltipEl.style.top = r.top + 'px';
                requestAnimationFrame(() => {
                    const tr = tooltipEl.getBoundingClientRect();
                    if (tr.bottom > window.innerHeight - 10) {
                        tooltipEl.style.top = Math.max(10, window.innerHeight - tr.height - 10) + 'px';
                    }
                    if (tr.right > window.innerWidth - 10) {
                        tooltipEl.style.left = (r.left - tr.width - 8) + 'px';
                    }
                });
            });
            badge.addEventListener('mouseleave', () => {
                tooltipEl.style.display = 'none';
            });

            overlay.appendChild(badge);
        });
    }

    updatePositions();
    cy.on('pan zoom', updatePositions);
    cy.one('layoutstop', updatePositions);
    container._defenseBadgeHandler = updatePositions;
}

function removeDefenseBadges(container) {
    const overlay = container.querySelector('.defense-badge-overlay');
    if (overlay) overlay.remove();
    const cy = cyInstances.get(container.id);
    if (cy && container._defenseBadgeHandler) {
        cy.off('pan zoom', container._defenseBadgeHandler);
        container._defenseBadgeHandler = null;
    }
}

function addShieldBadges(container, cy, graphData) {
    removeShieldBadges(container);
    if (!tooltipEl) initTooltip();

    const maps = buildInterventionMaps(graphData);
    const dateKey = dateOffsetKey(checkinDateOffset);
    const todaysCheckIns = new Set(storage.getCheckIns(dateKey));

    // Build: nodeId → [checked intervention labels]
    const shieldedNodes = new Map();
    maps.targetInterventions.forEach((txIds, nodeId) => {
        const activeTx = txIds.filter(id => todaysCheckIns.has(id));
        if (activeTx.length > 0) {
            const labels = activeTx.map(id => {
                const node = maps.interventionNodeMap.get(id);
                return node ? node.label.replace(/\n/g, ' ') : id;
            });
            shieldedNodes.set(nodeId, labels);
        }
    });

    if (shieldedNodes.size === 0) return;

    const overlay = document.createElement('div');
    overlay.className = 'shield-badge-overlay';
    container.appendChild(overlay);

    function updatePositions() {
        overlay.innerHTML = '';
        shieldedNodes.forEach((labels, nodeId) => {
            const node = cy.getElementById(nodeId);
            if (!node.length || node.removed()) return;
            if (node.data('styleClass') === 'groupLabel') return;

            const bb = node.renderedBoundingBox();
            const badge = document.createElement('div');
            badge.className = 'shield-badge';
            badge.textContent = labels.length > 1 ? `🛡️${labels.length}` : '🛡️';
            badge.style.left = `${bb.x1 + 2}px`;
            badge.style.top = `${bb.y1 - 2}px`;

            badge.addEventListener('mouseenter', () => {
                tooltipEl.innerHTML = `<div class="cy-tooltip-title">🛡️ Protected today</div>`
                    + labels.map(l => `<div class="cy-tooltip-row">${l}</div>`).join('');
                tooltipEl.style.display = 'block';
                const r = badge.getBoundingClientRect();
                tooltipEl.style.left = (r.right + 8) + 'px';
                tooltipEl.style.top = r.top + 'px';
            });
            badge.addEventListener('mouseleave', () => {
                tooltipEl.style.display = 'none';
            });

            overlay.appendChild(badge);
        });
    }

    updatePositions();
    cy.on('pan zoom', updatePositions);
    cy.one('layoutstop', updatePositions);
    container._shieldBadgeHandler = updatePositions;
}

function removeShieldBadges(container) {
    const overlay = container.querySelector('.shield-badge-overlay');
    if (overlay) overlay.remove();
    const cy = cyInstances.get(container.id);
    if (cy && container._shieldBadgeHandler) {
        cy.off('pan zoom', container._shieldBadgeHandler);
        container._shieldBadgeHandler = null;
    }
}

function toggleInterventions() {
    showInterventions = !showInterventions;
    if (!showInterventions) { pinnedInterventions.clear(); _checkinFilterNodeId = null; }
    if (showInterventions && showDefenseMode) showDefenseMode = false; // mutually exclusive
    reRenderGraphs();
}

function toggleDefenseMode() {
    showDefenseMode = !showDefenseMode;
    if (showDefenseMode && showInterventions) {
        showInterventions = false;
        pinnedInterventions.clear();
    }
    reRenderGraphs();
}

function reRenderGraphs() {
    if (_fullscreenContainer) {
        const config = GRAPH_CONFIGS.find(c => c.cyContainerId === _fullscreenContainer.id);
        if (config) renderGraph(config);
    } else {
        renderAllGraphs();
    }
}

function toggleFeedbackEdges() {
    showFeedbackEdges = !showFeedbackEdges;
    reRenderGraphs();
}

function toggleProtectiveEdges() {
    showProtectiveEdges = !showProtectiveEdges;
    reRenderGraphs();
}

// ═══════════════════════════════════════════════════════════
// FULLSCREEN
// ═══════════════════════════════════════════════════════════

let _fullscreenContainer = null;

function toggleFullscreen(container, cy) {
    if (container.classList.contains('fullscreen')) {
        exitFullscreen(container, cy);
    } else {
        enterFullscreen(container, cy);
    }
}

function enterFullscreen(container, cy) {
    _fullscreenContainer = container;
    container._scrollY = window.scrollY;
    container.classList.add('fullscreen');
    container.style.height = '100vh';

    // Re-enable interactive pan/zoom for fullscreen exploration
    cy.userPanningEnabled(true);
    attachWheelHandlerForFullscreen(container, cy);

    const hint = document.createElement('div');
    hint.className = 'fullscreen-hint';
    hint.textContent = 'Press Esc to exit fullscreen';
    container.appendChild(hint);
    setTimeout(() => { hint.style.transition = 'opacity 1s'; hint.style.opacity = '0'; }, 3000);
    setTimeout(() => { hint.remove(); }, 4000);

    const fsBtn = container.querySelector('[data-action="fullscreen"]');
    if (fsBtn) { fsBtn.innerHTML = '&#x2716;'; fsBtn.title = 'Exit fullscreen'; }

    setTimeout(() => { cy.resize(); runTieredLayout(cy, container); }, 50);
}

function exitFullscreen(container, cy) {
    _fullscreenContainer = null;
    container.classList.remove('fullscreen');
    container.style.height = '';  // Clear fixed height, let runTieredLayout set it

    // Disable interactive pan, let page scroll handle it
    cy.userPanningEnabled(false);
    if (container._wheelHandler) {
        container.removeEventListener('wheel', container._wheelHandler);
        container._wheelHandler = null;
    }

    const hint = container.querySelector('.fullscreen-hint');
    if (hint) hint.remove();

    const fsBtn = container.querySelector('[data-action="fullscreen"]');
    if (fsBtn) { fsBtn.innerHTML = '&#x26F6;'; fsBtn.title = 'Fullscreen'; }

    setTimeout(() => {
        cy.resize();
        runTieredLayout(cy, container);
        if (container._scrollY !== undefined) window.scrollTo(0, container._scrollY);
    }, 50);
}

// Global Escape key handler
if (runtimeDocument) {
    runtimeDocument.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && _fullscreenContainer) {
            const cy = cyInstances.get(_fullscreenContainer.id);
            if (cy) exitFullscreen(_fullscreenContainer, cy);
        }
    });
}

// ═══════════════════════════════════════════════════════════
// RESIZE HANDLER
// ═══════════════════════════════════════════════════════════

let _resizeTimeout = null;
if (runtimeWindow) {
    runtimeWindow.addEventListener('resize', () => {
        clearTimeout(_resizeTimeout);
        _resizeTimeout = setTimeout(() => {
            cyInstances.forEach((cy, containerId) => {
                const container = runtimeDocument?.getElementById(containerId);
                if (container && (container.offsetParent !== null || container.classList.contains('fullscreen'))) {
                    cy.resize();
                    runTieredLayout(cy, container);
                }
            });
        }, 250);
    });
}

// ═══════════════════════════════════════════════════════════
// RENDER
// ═══════════════════════════════════════════════════════════

function renderAllGraphs() {
    GRAPH_CONFIGS.forEach(config => {
        const container = document.getElementById(config.containerId);
        if (container && !container.classList.contains('edit-mode')) {
            renderGraph(config);
        }
    });
}

function renderGraph(config) {
    const cyContainer = document.getElementById(config.cyContainerId);
    if (!cyContainer) return;

    const wasFullscreen = cyContainer.classList.contains('fullscreen');
    destroyCyInstance(config.cyContainerId);

    // Only init if visible (hidden containers cause zero dimensions).
    // offsetParent is null for position:fixed (fullscreen) — handle that case.
    if (cyContainer.offsetParent !== null || wasFullscreen) {
        const cy = createCyInstance(config.cyContainerId, currentGraphData);
        // Restore fullscreen state after recreation
        if (wasFullscreen && cy) {
            _fullscreenContainer = cyContainer;
            cyContainer.style.height = '100vh';
            cy.userPanningEnabled(true);
            attachWheelHandlerForFullscreen(cyContainer, cy);
            const fsBtn = cyContainer.querySelector('[data-action="fullscreen"]');
            if (fsBtn) { fsBtn.innerHTML = '\u2716'; fsBtn.title = 'Exit fullscreen'; }
            setTimeout(() => { cy.resize(); runTieredLayout(cy, cyContainer); }, 50);
        }
    }
}

// ═══════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════

function escapeHtml(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function getGraphData() {
    return currentGraphData;
}

/**
 * Refresh Cytoscape instances after layout changes (e.g. tab switch).
 */
export function refreshPanZoom() {
    setTimeout(() => {
        GRAPH_CONFIGS.forEach(config => {
            const container = document.getElementById(config.cyContainerId);
            if (!container) return;

            if (container.offsetParent !== null || container.classList.contains('fullscreen')) {
                const cy = cyInstances.get(config.cyContainerId);
                if (cy) {
                    cy.resize();
                    runTieredLayout(cy, container);
                } else {
                    createCyInstance(config.cyContainerId, currentGraphData);
                }
            }
        });
    }, 100);
}
