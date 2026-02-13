import { computeDefenseScores } from './causalEditor/defenseScoring.js';
import { CASCADE_DECAY } from './causalEditor/defenseConstants.js';

const STORAGE_KEY = 'bruxism_personal_data';
const STORAGE_VERSION = 1;
const MIN_PROPAGATION_STRENGTH = 0.01;
const EPSILON = 1e-9;

const EFFECTIVENESS_WEIGHTS = {
    untested: 0.5,
    ineffective: 0.1,
    modest: 0.4,
    effective: 0.75,
    highly_effective: 1.0,
};

function interventionNode(id, label = id) {
    return { id, label, type: 'intervention' };
}

function mechanismNode(id, label = id) {
    return { id, label, type: 'mechanism' };
}

function edge(source, target, edgeType = 'forward') {
    return { source, target, edgeType };
}

function approxEqual(actual, expected) {
    return Math.abs(actual - expected) <= EPSILON;
}

function clamp01(value) {
    return Math.max(0, Math.min(1, value));
}

function combineIndependent(parts) {
    let remainingRisk = 1;
    parts.forEach(part => {
        remainingRisk *= (1 - clamp01(part));
    });
    return 1 - remainingRisk;
}

function toPercent(value) {
    return `${(value * 100).toFixed(1)}%`;
}

function dateKey(daysAgo) {
    const date = new Date();
    date.setDate(date.getDate() - daysAgo);
    return date.toISOString().split('T')[0];
}

function buildScenarioStorage(activations) {
    const dailyCheckIns = {};
    const interventionRatings = [];

    activations.forEach(activation => {
        interventionRatings.push({
            interventionId: activation.id,
            effectiveness: activation.effectiveness,
            notes: '',
            lastUpdated: new Date().toISOString(),
        });

        const daysActive = Math.max(0, Math.min(7, activation.daysActive));
        for (let i = 0; i < daysActive; i += 1) {
            const key = dateKey(i);
            if (!dailyCheckIns[key]) dailyCheckIns[key] = [];
            dailyCheckIns[key].push(activation.id);
        }
    });

    return {
        version: STORAGE_VERSION,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings,
        dailyCheckIns,
        hiddenInterventions: [],
        unlockedAchievements: [],
    };
}

function withScenarioStorage(activations, fn) {
    const original = window.localStorage.getItem(STORAGE_KEY);
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(buildScenarioStorage(activations)));
        return fn();
    } finally {
        if (original === null) {
            window.localStorage.removeItem(STORAGE_KEY);
        } else {
            window.localStorage.setItem(STORAGE_KEY, original);
        }
    }
}

function buildGraphData(scenario) {
    return {
        nodes: scenario.nodes.map(node => ({
            data: {
                id: node.id,
                label: node.label,
                styleClass: node.type === 'intervention' ? 'intervention' : 'mechanism',
            },
        })),
        edges: scenario.edges.map(item => ({
            data: {
                source: item.source,
                target: item.target,
                edgeType: item.edgeType,
            },
        })),
    };
}

function computeLegacyScores(graphData, activations) {
    const interventionNodes = new Set(
        graphData.nodes
            .filter(node => node.data.styleClass === 'intervention')
            .map(node => node.data.id)
    );

    const strengthMap = new Map();
    activations.forEach(activation => {
        const weight = EFFECTIVENESS_WEIGHTS[activation.effectiveness] || EFFECTIVENESS_WEIGHTS.untested;
        const strength = weight * (Math.max(0, Math.min(7, activation.daysActive)) / 7);
        strengthMap.set(activation.id, strength);
    });

    const directScores = new Map();
    graphData.edges.forEach(item => {
        const edgeData = item.data;
        if (!interventionNodes.has(edgeData.source)) return;
        const existing = directScores.get(edgeData.target) || 0;
        const addition = strengthMap.get(edgeData.source) || 0;
        directScores.set(edgeData.target, Math.min(1, existing + addition));
    });

    const adjacency = new Map();
    graphData.edges.forEach(item => {
        const edgeData = item.data;
        if (edgeData.edgeType === 'feedback' || edgeData.edgeType === 'protective') return;
        if (interventionNodes.has(edgeData.source)) return;
        if (!adjacency.has(edgeData.source)) adjacency.set(edgeData.source, []);
        adjacency.get(edgeData.source).push(edgeData.target);
    });

    const allScores = new Map();
    graphData.nodes.forEach(node => {
        if (node.data.styleClass === 'intervention') return;
        allScores.set(node.data.id, { score: 0, isDirect: false });
    });

    directScores.forEach((score, nodeId) => {
        allScores.set(nodeId, { score, isDirect: true });
    });

    const queue = [];
    directScores.forEach((score, nodeId) => {
        if (score > 0) queue.push({ nodeId, strength: score });
    });

    const bestStrength = new Map();
    while (queue.length > 0) {
        const { nodeId, strength } = queue.shift();
        const children = adjacency.get(nodeId) || [];
        children.forEach(childId => {
            const cascaded = strength * CASCADE_DECAY;
            if (cascaded < MIN_PROPAGATION_STRENGTH) return;
            const existing = allScores.get(childId);
            if (!existing) return;

            const newScore = Math.min(1, existing.score + cascaded);
            if (newScore > existing.score + EPSILON) {
                allScores.set(childId, { score: newScore, isDirect: existing.isDirect });
                const prevBest = bestStrength.get(childId) || 0;
                if (cascaded > prevBest + EPSILON) {
                    bestStrength.set(childId, cascaded);
                    queue.push({ nodeId: childId, strength: cascaded });
                }
            }
        });
    }

    return allScores;
}

function score(map, nodeId) {
    return map.get(nodeId)?.score || 0;
}

function scenarioExpectedValues(scenarioId) {
    const root = 0.1;
    const oneHop = root * CASCADE_DECAY;
    const twoHops = oneHop * CASCADE_DECAY;

    if (scenarioId === 'split-rejoin') {
        return new Map([
            ['A', root],
            ['B', oneHop],
            ['C', oneHop],
            ['D', twoHops],
        ]);
    }

    if (scenarioId === 'same-source-multipath') {
        return new Map([['B', oneHop]]);
    }

    if (scenarioId === 'independent-sources') {
        return new Map([['C', combineIndependent([oneHop, oneHop])]]);
    }

    if (scenarioId === 'feedback-protective-excluded') {
        return new Map([
            ['A', root],
            ['B', 0],
            ['C', 0],
        ]);
    }

    return new Map();
}

const scenarios = [
    {
        id: 'split-rejoin',
        title: 'Split -> Rejoin (Single Source)',
        summary: 'A single defended source branches then reconverges. Downstream score should not exceed source score.',
        biology: 'One biological defense source should attenuate with distance, not duplicate itself because pathways split and merge.',
        modelReasoning: 'Per-source max-path tracking prevents counting the same source twice at reconvergence.',
        activations: [{ id: 'TX_A', effectiveness: 'ineffective', daysActive: 7 }],
        nodes: [
            interventionNode('TX_A'),
            mechanismNode('A'),
            mechanismNode('B'),
            mechanismNode('C'),
            mechanismNode('D'),
        ],
        edges: [
            edge('TX_A', 'A'),
            edge('A', 'B'),
            edge('A', 'C'),
            edge('B', 'D'),
            edge('C', 'D'),
        ],
        layout: {
            width: 640,
            height: 260,
            positions: {
                TX_A: { x: 70, y: 130 },
                A: { x: 200, y: 130 },
                B: { x: 340, y: 74 },
                C: { x: 340, y: 186 },
                D: { x: 500, y: 130 },
            },
        },
        checks(result) {
            return [
                {
                    label: 'Current model keeps D at one source path strength (0.1 * 0.8 * 0.8).',
                    pass: approxEqual(score(result.current, 'D'), scenarioExpectedValues(this.id).get('D')),
                },
                {
                    label: 'Current model keeps D <= A for this single-source network.',
                    pass: score(result.current, 'D') <= score(result.current, 'A') + EPSILON,
                },
                {
                    label: 'Legacy additive model inflates D above current model in the same topology.',
                    pass: score(result.legacy, 'D') > score(result.current, 'D') + EPSILON,
                },
            ];
        },
    },
    {
        id: 'same-source-multipath',
        title: 'Same Source, Two Paths to One Node',
        summary: 'Node B receives one short path and one longer path from the same source A.',
        biology: 'Redundant causal routes from the same defended source should not stack as independent biological protections.',
        modelReasoning: 'Use strongest path from a source per downstream node, not additive path sum.',
        activations: [{ id: 'TX_A', effectiveness: 'ineffective', daysActive: 7 }],
        nodes: [
            interventionNode('TX_A'),
            mechanismNode('A'),
            mechanismNode('X'),
            mechanismNode('B'),
        ],
        edges: [
            edge('TX_A', 'A'),
            edge('A', 'B'),
            edge('A', 'X'),
            edge('X', 'B'),
        ],
        layout: {
            width: 640,
            height: 260,
            positions: {
                TX_A: { x: 80, y: 130 },
                A: { x: 220, y: 130 },
                X: { x: 360, y: 74 },
                B: { x: 500, y: 130 },
            },
        },
        checks(result) {
            const expectedB = scenarioExpectedValues(this.id).get('B');
            return [
                {
                    label: 'Current model sets B to best same-source path only (0.1 * 0.8).',
                    pass: approxEqual(score(result.current, 'B'), expectedB),
                },
                {
                    label: 'Legacy additive model overcounts B when both paths are present.',
                    pass: score(result.legacy, 'B') > score(result.current, 'B') + EPSILON,
                },
            ];
        },
    },
    {
        id: 'independent-sources',
        title: 'Convergence of Independent Sources',
        summary: 'Two distinct defended upstream causes converge on C.',
        biology: 'Independent mechanisms can jointly improve protection, but with diminishing returns instead of linear addition.',
        modelReasoning: 'Noisy-OR merge captures joint coverage while staying bounded below additive summation.',
        activations: [
            { id: 'TX_A', effectiveness: 'ineffective', daysActive: 7 },
            { id: 'TX_B', effectiveness: 'ineffective', daysActive: 7 },
        ],
        nodes: [
            interventionNode('TX_A'),
            interventionNode('TX_B'),
            mechanismNode('A'),
            mechanismNode('B'),
            mechanismNode('C'),
        ],
        edges: [
            edge('TX_A', 'A'),
            edge('TX_B', 'B'),
            edge('A', 'C'),
            edge('B', 'C'),
        ],
        layout: {
            width: 640,
            height: 260,
            positions: {
                TX_A: { x: 80, y: 78 },
                A: { x: 220, y: 78 },
                TX_B: { x: 80, y: 186 },
                B: { x: 220, y: 186 },
                C: { x: 430, y: 132 },
            },
        },
        checks(result) {
            const expectedC = scenarioExpectedValues(this.id).get('C');
            const oneSource = 0.1 * CASCADE_DECAY;
            return [
                {
                    label: 'Current model matches noisy-OR merged expectation at C.',
                    pass: approxEqual(score(result.current, 'C'), expectedC),
                },
                {
                    label: 'Combined score is above one source but below linear sum.',
                    pass: score(result.current, 'C') > oneSource + EPSILON
                        && score(result.current, 'C') < (2 * oneSource) - EPSILON,
                },
            ];
        },
    },
    {
        id: 'feedback-protective-excluded',
        title: 'Feedback/Protective Edge Exclusion',
        summary: 'Only forward causal edges should carry defense cascade in this model.',
        biology: 'Feedback and protective annotations represent different semantics and are excluded from forward defense transport.',
        modelReasoning: 'Adjacency for propagation explicitly ignores feedback/protective edge types.',
        activations: [{ id: 'TX_A', effectiveness: 'ineffective', daysActive: 7 }],
        nodes: [
            interventionNode('TX_A'),
            mechanismNode('A'),
            mechanismNode('B'),
            mechanismNode('C'),
        ],
        edges: [
            edge('TX_A', 'A'),
            edge('A', 'B', 'feedback'),
            edge('A', 'C', 'protective'),
        ],
        layout: {
            width: 640,
            height: 260,
            positions: {
                TX_A: { x: 80, y: 130 },
                A: { x: 220, y: 130 },
                B: { x: 430, y: 76 },
                C: { x: 430, y: 184 },
            },
        },
        checks(result) {
            const expected = scenarioExpectedValues(this.id);
            return [
                {
                    label: 'Current model preserves A direct protection.',
                    pass: approxEqual(score(result.current, 'A'), expected.get('A')),
                },
                {
                    label: 'Current model keeps B and C at 0 through excluded edge types.',
                    pass: approxEqual(score(result.current, 'B'), 0) && approxEqual(score(result.current, 'C'), 0),
                },
            ];
        },
    },
];

function escapeHtml(text) {
    return text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function drawEdge(edgeItem, layout, boxWidth, boxHeight) {
    const source = layout.positions[edgeItem.source];
    const target = layout.positions[edgeItem.target];
    if (!source || !target) return '';

    const dx = target.x - source.x;
    const dy = target.y - source.y;
    const distance = Math.max(1, Math.sqrt((dx * dx) + (dy * dy)));
    const ux = dx / distance;
    const uy = dy / distance;

    const startX = source.x + ux * (boxWidth / 2 - 8);
    const startY = source.y + uy * (boxHeight / 2 - 8);
    const endX = target.x - ux * (boxWidth / 2 - 8);
    const endY = target.y - uy * (boxHeight / 2 - 8);

    const edgeClass = edgeItem.edgeType === 'feedback'
        ? 'edge feedback'
        : edgeItem.edgeType === 'protective'
            ? 'edge protective'
            : 'edge forward';

    return `<line class="${edgeClass}" x1="${startX}" y1="${startY}" x2="${endX}" y2="${endY}" marker-end="url(#arrow-${edgeItem.edgeType})"></line>`;
}

function drawNode(node, layout, currentScores, legacyScores) {
    const position = layout.positions[node.id];
    if (!position) return '';

    const isIntervention = node.type === 'intervention';
    const width = isIntervention ? 108 : 120;
    const height = isIntervention ? 48 : 78;
    const x = position.x - (width / 2);
    const y = position.y - (height / 2);

    const baseClass = isIntervention ? 'node intervention' : 'node mechanism';

    if (isIntervention) {
        return `
            <g>
                <rect class="${baseClass}" x="${x}" y="${y}" width="${width}" height="${height}" rx="11"></rect>
                <text class="node-label intervention" x="${position.x}" y="${position.y + 4}" text-anchor="middle">${escapeHtml(node.label)}</text>
            </g>
        `;
    }

    const current = toPercent(score(currentScores, node.id));
    const legacy = toPercent(score(legacyScores, node.id));

    return `
        <g>
            <rect class="${baseClass}" x="${x}" y="${y}" width="${width}" height="${height}" rx="11"></rect>
            <text class="node-label" x="${position.x}" y="${position.y - 17}" text-anchor="middle">${escapeHtml(node.label)}</text>
            <text class="node-score current" x="${position.x}" y="${position.y + 1}" text-anchor="middle">Current: ${current}</text>
            <text class="node-score legacy" x="${position.x}" y="${position.y + 19}" text-anchor="middle">Legacy: ${legacy}</text>
        </g>
    `;
}

function renderGraphSvg(scenario, currentScores, legacyScores) {
    const { layout } = scenario;
    const boxWidth = 120;
    const boxHeight = 78;

    const edgesSvg = scenario.edges
        .map(edgeItem => drawEdge(edgeItem, layout, boxWidth, boxHeight))
        .join('');

    const nodesSvg = scenario.nodes
        .map(node => drawNode(node, layout, currentScores, legacyScores))
        .join('');

    return `
<svg viewBox="0 0 ${layout.width} ${layout.height}" role="img" aria-label="${escapeHtml(scenario.title)} graph">
    <defs>
        <marker id="arrow-forward" markerWidth="9" markerHeight="7" refX="8" refY="3.5" orient="auto">
            <polygon points="0 0, 9 3.5, 0 7" fill="#475569"></polygon>
        </marker>
        <marker id="arrow-feedback" markerWidth="9" markerHeight="7" refX="8" refY="3.5" orient="auto">
            <polygon points="0 0, 9 3.5, 0 7" fill="#dc2626"></polygon>
        </marker>
        <marker id="arrow-protective" markerWidth="9" markerHeight="7" refX="8" refY="3.5" orient="auto">
            <polygon points="0 0, 9 3.5, 0 7" fill="#2563eb"></polygon>
        </marker>
    </defs>
    ${edgesSvg}
    ${nodesSvg}
</svg>
    `;
}

function computeScenarioResult(scenario) {
    const graphData = buildGraphData(scenario);

    return withScenarioStorage(scenario.activations, () => {
        const current = computeDefenseScores(graphData);
        const legacy = computeLegacyScores(graphData, scenario.activations);
        const expected = scenarioExpectedValues(scenario.id);
        return { current, legacy, expected };
    });
}

function renderNodeNumbers(scenario, result) {
    const mechanismNodes = scenario.nodes.filter(node => node.type === 'mechanism');
    let html = '<h3>Node Scores</h3><ul>';

    mechanismNodes.forEach(node => {
        const current = score(result.current, node.id);
        const legacy = score(result.legacy, node.id);
        const expected = result.expected.get(node.id);

        html += `<li><strong>${escapeHtml(node.label)}:</strong> Current ${toPercent(current)} | Legacy ${toPercent(legacy)}`;
        if (typeof expected === 'number') {
            html += ` | Expected ${toPercent(expected)}`;
        }
        html += '</li>';
    });

    html += '</ul>';
    return html;
}

function renderChecks(scenario, result) {
    const checks = scenario.checks(result);
    let html = '<h3>Validation Checks</h3><ul>';

    checks.forEach(check => {
        html += `<li class="${check.pass ? 'pass' : 'fail'}">${check.pass ? 'PASS' : 'FAIL'}: ${escapeHtml(check.label)}</li>`;
    });

    html += '</ul>';
    return html;
}

function renderScenarioCard(scenario, result) {
    const graphSvg = renderGraphSvg(scenario, result.current, result.legacy);
    const numbers = renderNodeNumbers(scenario, result);
    const checks = renderChecks(scenario, result);

    return `
<article class="scenario-card">
    <div class="scenario-header">
        <div class="scenario-title">${escapeHtml(scenario.title)}</div>
        <p class="scenario-sub">${escapeHtml(scenario.summary)}</p>
        <p><strong>Biology:</strong> ${escapeHtml(scenario.biology)}</p>
        <p><strong>Reasoning:</strong> ${escapeHtml(scenario.modelReasoning)}</p>
    </div>
    <div class="scenario-body">
        <div>
            <div class="graph-wrap">
                ${graphSvg}
            </div>
            <div class="legend">
                <span><i class="dot" style="background:#0f766e"></i> Intervention</span>
                <span><i class="dot" style="background:#ffffff;border:1px solid #94a3b8"></i> Mechanism node</span>
                <span><i class="line"></i> Forward edge</span>
                <span><i class="line feedback"></i> Feedback edge (excluded)</span>
                <span><i class="line protective"></i> Protective edge (excluded)</span>
            </div>
        </div>
        <div>
            <div class="numbers">${numbers}</div>
            <div class="checks" style="margin-top:10px;">${checks}</div>
        </div>
    </div>
</article>
    `;
}

function mount() {
    const decayEl = document.getElementById('decay-pill');
    if (decayEl) decayEl.textContent = String(CASCADE_DECAY);

    const grid = document.getElementById('scenario-grid');
    if (!grid) return;

    const cards = scenarios.map(scenario => {
        const result = computeScenarioResult(scenario);
        return renderScenarioCard(scenario, result);
    });

    grid.innerHTML = cards.join('');
}

mount();
