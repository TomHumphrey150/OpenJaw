import * as storage from '../storage.js';
import { buildInterventionMaps } from './interventionMaps.js';
import { NODE_TIERS } from './layoutConfig.js';
import { EFFECTIVENESS_WEIGHTS, CASCADE_DECAY } from './defenseConstants.js';

// ── Network Impact Scoring (for sidebar ranking) ──

export function computeNetworkImpact(graphData) {
    const maps = buildInterventionMaps(graphData);

    // Build forward adjacency (exclude feedback/protective/intervention edges)
    const adjacency = new Map();
    graphData.edges.forEach(e => {
        const src = e.data.source;
        const tgt = e.data.target;
        if (e.data.edgeType === 'feedback' || e.data.edgeType === 'protective') return;
        if (maps.interventionNodeMap.has(src)) return;
        if (!adjacency.has(src)) adjacency.set(src, []);
        adjacency.get(src).push(tgt);
    });

    // Tier weight: nodes closer to symptoms are worth more
    function tierWeight(nodeId) {
        const t = NODE_TIERS[nodeId];
        if (t === undefined) return 1.0;
        if (t >= 8) return 1.5;
        if (t >= 6) return 1.2;
        return 1.0;
    }

    // Out-degree hub bonus
    function hubBonus(nodeId) {
        const children = adjacency.get(nodeId) || [];
        return 1 + 0.1 * children.length;
    }

    const impact = new Map();

    maps.interventionNodeMap.forEach((_, txId) => {
        const targets = maps.interventionTargets.get(txId) || [];
        const directTargetIds = targets.map(t => t.target);

        // BFS forward from direct targets
        let score = 0;
        let reachableCount = 0;
        const visited = new Set();
        const queue = []; // { nodeId, decay }

        directTargetIds.forEach(tId => {
            if (!visited.has(tId)) {
                visited.add(tId);
                queue.push({ nodeId: tId, decay: 1.0 });
            }
        });

        while (queue.length > 0) {
            const { nodeId, decay } = queue.shift();
            score += decay * tierWeight(nodeId) * hubBonus(nodeId);
            reachableCount++;

            const children = adjacency.get(nodeId) || [];
            children.forEach(childId => {
                if (visited.has(childId)) return;
                const nextDecay = decay * CASCADE_DECAY;
                if (nextDecay < 0.01) return;
                visited.add(childId);
                queue.push({ nodeId: childId, decay: nextDecay });
            });
        }

        impact.set(txId, { score, reachableCount });
    });

    return impact;
}

// ── Defense Score Computation ──

export function computeDefenseScores(graphData) {
    const maps = buildInterventionMaps(graphData);
    const rangeData = storage.getCheckInsRange(7);
    const ratings = storage.getAllRatings();
    const ratingMap = {};
    ratings.forEach(r => { ratingMap[r.interventionId] = r.effectiveness; });

    // For each intervention, compute: weight * (days_active / 7)
    function interventionStrength(txId) {
        const eff = ratingMap[txId] || 'untested';
        const weight = EFFECTIVENESS_WEIGHTS[eff] || 0.5;
        let daysActive = 0;
        Object.values(rangeData).forEach(ids => { if (ids.includes(txId)) daysActive++; });
        return weight * (daysActive / 7);
    }

    // Compute direct defense for each target node
    const directScores = new Map(); // nodeId → score (0..1)
    maps.targetInterventions.forEach((txIds, nodeId) => {
        let total = 0;
        txIds.forEach(txId => { total += interventionStrength(txId); });
        directScores.set(nodeId, Math.min(1, total));
    });

    // Build adjacency from graph edges (forward direction only)
    const adjacency = new Map(); // source → [target]
    graphData.edges.forEach(e => {
        const src = e.data.source;
        const tgt = e.data.target;
        if (e.data.edgeType === 'feedback' || e.data.edgeType === 'protective') return;
        if (maps.interventionNodeMap.has(src)) return; // skip intervention edges
        if (!adjacency.has(src)) adjacency.set(src, []);
        adjacency.get(src).push(tgt);
    });

    // Cascade: BFS from directly defended nodes downstream
    const allScores = new Map(); // nodeId → { score, isDirect }

    // Initialize all mechanism nodes with 0
    graphData.nodes.forEach(n => {
        if (n.data.styleClass !== 'intervention') {
            allScores.set(n.data.id, { score: 0, isDirect: false });
        }
    });

    // Set direct scores
    directScores.forEach((score, nodeId) => {
        allScores.set(nodeId, { score, isDirect: true });
    });

    // BFS cascade: propagate defense downstream with decay
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
            if (cascaded < 0.01) return;
            const existing = allScores.get(childId);
            if (!existing) return;
            const newScore = Math.min(1, existing.score + cascaded);
            if (newScore > existing.score) {
                allScores.set(childId, { score: newScore, isDirect: existing.isDirect });
                const prev = bestStrength.get(childId) || 0;
                if (cascaded > prev) {
                    bestStrength.set(childId, cascaded);
                    queue.push({ nodeId: childId, strength: cascaded });
                }
            }
        });
    }

    return allScores;
}

export function scoreToColor(score, isDirect) {
    const opacity = isDirect ? 1.0 : 0.7;
    if (score >= 0.6) return { color: '#22c55e', border: '#16a34a', opacity }; // green
    if (score >= 0.3) return { color: '#f59e0b', border: '#d97706', opacity }; // amber
    return { color: '#ef4444', border: '#dc2626', opacity }; // red
}

export function scoreToLabel(score) {
    return Math.round(score * 100) + '%';
}
