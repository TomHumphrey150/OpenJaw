export const CYTOSCAPE_STYLES = [
    // Base node
    {
        selector: 'node',
        style: {
            'label': 'data(label)',
            'text-wrap': 'wrap',
            'text-max-width': '200px',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': '13px',
            'color': '#fff',
            'background-color': '#374151',
            'border-width': 2,
            'border-color': '#1f2937',
            'shape': 'round-rectangle',
            'padding': '12px',
            'width': 'label',
            'height': 'label',
        }
    },
    // ── Confirmed status styles ──
    {
        selector: 'node[confirmed="no"]',
        style: { 'opacity': 0.4, 'border-style': 'dashed' }
    },
    {
        selector: 'node[confirmed="inactive"]',
        style: { 'opacity': 0.2, 'border-style': 'dashed' }
    },
    {
        selector: 'node[confirmed="external"]',
        style: { 'opacity': 0.5, 'border-style': 'dotted' }
    },
    // ── Node style classes ──
    {
        selector: 'node[styleClass="robust"]',
        style: { 'background-color': '#1b4332', 'border-color': '#081c15', 'border-width': 3 }
    },
    {
        selector: 'node[styleClass="moderate"]',
        style: { 'background-color': '#b45309', 'border-color': '#78350f', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="preliminary"]',
        style: { 'background-color': '#6b21a8', 'border-color': '#4c1d95', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="symptom"]',
        style: { 'background-color': '#1e3a5f', 'border-color': '#0f172a', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="mechanism"]',
        style: { 'background-color': '#374151', 'border-color': '#1f2937', 'border-width': 2 }
    },
    {
        selector: 'node[styleClass="intervention"]',
        style: { 'background-color': '#065f46', 'color': '#d1fae5', 'border-color': '#047857', 'border-width': 2, 'border-style': 'dashed' }
    },
    // Group label nodes (oval mode only)
    {
        selector: 'node[styleClass="groupLabel"]',
        style: {
            'background-color': 'rgba(30, 41, 59, 0.85)',
            'background-opacity': 1,
            'border-width': 1,
            'border-color': 'rgba(100, 116, 139, 0.25)',
            'border-style': 'solid',
            'shape': 'round-rectangle',
            'label': 'data(label)',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': '11px',
            'font-weight': '700',
            'color': 'rgba(148, 163, 184, 0.8)',
            'text-transform': 'uppercase',
            'width': 'label',
            'height': 'label',
            'padding': '6px',
            'events': 'no',
            'z-index': 0,
        }
    },
    // ── Base edge (data-driven coloring) ──
    {
        selector: 'edge',
        style: {
            'width': 1,
            'line-color': 'data(edgeColor)',
            'target-arrow-color': 'data(edgeColor)',
            'target-arrow-shape': 'triangle',
            'curve-style': 'bezier',
            'arrow-scale': 0.7,
            'opacity': 0.6,
            'font-size': '8px',
            'color': '#94a3b8',
            'text-background-color': '#1a1a2e',
            'text-background-opacity': 0.9,
            'text-background-padding': '2px',
        }
    },
    // Fallback for edges without edgeColor
    {
        selector: 'edge:not([edgeColor])',
        style: { 'line-color': '#888', 'target-arrow-color': '#888' }
    },
    // Edge labels hidden by default — shown on hover via tooltip
    {
        selector: 'edge[label]',
        style: { 'label': '' }
    },
    // Dashed edges (preliminary evidence)
    {
        selector: 'edge[edgeType="dashed"]',
        style: { 'line-style': 'dashed', 'opacity': 0.45 }
    },
    // Feedback loop edges (red dashed) — most prominent
    {
        selector: 'edge[edgeType="feedback"]',
        style: {
            'line-style': 'dashed',
            'line-color': '#ef4444',
            'target-arrow-color': '#ef4444',
            'width': 1.5,
            'opacity': 0.8,
        }
    },
    // Protective mechanism edges (blue dashed) — body's defense
    {
        selector: 'edge[edgeType="protective"]',
        style: {
            'line-style': 'dashed',
            'line-color': '#3b82f6',
            'target-arrow-color': '#3b82f6',
            'width': 1.5,
            'opacity': 0.8,
        }
    },
    // ── Node/edge hover highlight ──
    {
        selector: 'node.hover-highlight',
        style: { 'border-width': 3, 'border-color': '#60a5fa', 'z-index': 999 }
    },
    {
        selector: 'edge.hover-highlight',
        style: { 'opacity': 1, 'width': 2, 'z-index': 999, 'label': 'data(label)' }
    },
    {
        selector: 'node.hover-neighbor',
        style: { 'border-width': 2, 'border-color': '#60a5fa', 'z-index': 998 }
    },
    {
        selector: 'node.hover-neighbor-2',
        style: { 'border-width': 1, 'border-color': '#60a5fa', 'z-index': 997, 'opacity': 0.55 }
    },
    {
        selector: 'edge.hover-highlight-2',
        style: { 'opacity': 0.35, 'width': 1.5, 'z-index': 997 }
    },
    {
        selector: 'node.hover-dimmed',
        style: { 'opacity': 0.25 }
    },
    {
        selector: 'edge.hover-dimmed',
        style: { 'opacity': 0.08 }
    },
    // ── Intervention highlight system ──
    // Baseline dim: mechanism nodes/edges when interventions visible
    { selector: 'node.tx-dimmed', style: { opacity: 0.4 } },
    { selector: 'edge.tx-dimmed', style: { opacity: 0.15 } },
    // Deep dim: everything not highlighted during hover/pin
    { selector: 'node.tx-deep-dimmed', style: { opacity: 0.08 } },
    { selector: 'edge.tx-deep-dimmed', style: { opacity: 0.05 } },
    // Highlighted intervention node
    { selector: 'node.tx-highlighted', style: { opacity: 1, 'border-width': 3, 'border-color': '#38bdf8', 'z-index': 999 } },
    // Highlighted intervention edge
    { selector: 'edge.tx-highlighted', style: { opacity: 1, width: 2.5, 'z-index': 999 } },
    // Highlighted target node
    { selector: 'node.tx-target-highlighted', style: { opacity: 1, 'border-width': 2, 'border-color': '#38bdf8', 'z-index': 998 } },
    // Pinned intervention node (amber border)
    { selector: 'node.tx-pinned', style: { 'border-width': 3, 'border-color': '#f59e0b', 'z-index': 999 } },

    // ── Defense heatmap ──
    { selector: 'node.defense-node', style: {
        'border-color': 'data(defenseColor)',
        'border-width': 3,
        'background-opacity': 'data(defenseOpacity)',
    }},
    { selector: 'edge.defense-edge', style: {
        'line-color': 'data(defenseColor)',
        'target-arrow-color': 'data(defenseColor)',
        'width': 'data(defenseWidth)',
        'opacity': 'data(defenseOpacity)',
    }},
    // ── Defense state classes with underlay glow ──
    { selector: 'node.defense-fortified', style: {
        'border-width': 4,
        'border-color': '#22c55e',
        'border-style': 'solid',
        'underlay-color': '#22c55e',
        'underlay-padding': 6,
        'underlay-opacity': 0.12,
    }},
    { selector: 'node.defense-contested', style: {
        'border-width': 3,
        'border-color': '#f59e0b',
        'border-style': 'dashed',
        'underlay-color': '#f59e0b',
        'underlay-padding': 5,
        'underlay-opacity': 0.08,
    }},
    { selector: 'node.defense-exposed', style: {
        'border-width': 2,
        'border-color': '#ef4444',
        'border-style': 'solid',
        'underlay-color': '#ef4444',
        'underlay-padding': 5,
        'underlay-opacity': 0.10,
    }},
];
