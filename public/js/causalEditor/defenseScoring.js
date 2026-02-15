import * as storage from '../storage.js';
import { buildInterventionMaps } from './interventionMaps.js';
import { EFFECTIVENESS_WEIGHTS, CASCADE_DECAY } from './defenseConstants.js';

const MIN_PROPAGATION_STRENGTH = 0.01;
const NUMERIC_EPSILON = 1e-9;

// Evidence confidence priors (label-based), then refined by stat/citation signal.
const EVIDENCE_LABEL_MULTIPLIERS = {
    robust: 1.25,
    moderate_high: 1.15,
    moderate: 1.0,
    low_moderate: 0.9,
    preliminary: 0.8,
    low: 0.75,
    mechanism: 0.85,
    default: 1.0,
};

function evidenceLabelMultiplier(evidenceLabel) {
    if (!evidenceLabel || typeof evidenceLabel !== 'string') {
        return EVIDENCE_LABEL_MULTIPLIERS.default;
    }

    const normalized = evidenceLabel.toLowerCase();
    if (normalized.includes('robust')) return EVIDENCE_LABEL_MULTIPLIERS.robust;
    if (normalized.includes('moderate-high') || normalized.includes('moderate high')) {
        return EVIDENCE_LABEL_MULTIPLIERS.moderate_high;
    }
    if (normalized.includes('low-moderate') || normalized.includes('low moderate')) {
        return EVIDENCE_LABEL_MULTIPLIERS.low_moderate;
    }
    if (normalized.includes('preliminary')) return EVIDENCE_LABEL_MULTIPLIERS.preliminary;
    if (normalized.includes('mechanism')) return EVIDENCE_LABEL_MULTIPLIERS.mechanism;
    if (normalized.includes('moderate')) return EVIDENCE_LABEL_MULTIPLIERS.moderate;
    if (normalized.includes('low')) return EVIDENCE_LABEL_MULTIPLIERS.low;
    return EVIDENCE_LABEL_MULTIPLIERS.default;
}

function parseLargestSampleSize(text) {
    if (!text || typeof text !== 'string') return null;
    const regex = /N\s*=\s*([0-9,]+)/gi;
    let match;
    let largest = null;
    while ((match = regex.exec(text)) !== null) {
        const parsed = Number(match[1].replace(/,/g, ''));
        if (Number.isFinite(parsed)) {
            largest = largest === null ? parsed : Math.max(largest, parsed);
        }
    }
    return largest;
}

function sampleSizeMultiplier(statText) {
    const n = parseLargestSampleSize(statText);
    if (n === null) return 1.0;
    if (n <= 20) return 0.9;
    if (n <= 100) return 0.97;
    if (n <= 300) return 1.04;
    return 1.1;
}

function effectSignalMultiplier(evidenceText, statText, citationText) {
    const combined = `${evidenceText || ''} ${statText || ''} ${citationText || ''}`.toLowerCase();
    let multiplier = 1.0;

    if (/(meta-analysis|systematic review|cochrane|rct)/.test(combined)) {
        multiplier += 0.03;
    }
    if (/(clinical experience|theoretical|pilot|guidance|protocol)/.test(combined)) {
        multiplier -= 0.04;
    }
    if (/(significant|sig\\.|smd|or\\s*[0-9]|vas\\s*[-0-9]|events?\\s*[0-9]+\\s*[→>-]\\s*[0-9]+|-[0-9]+%)/.test(combined)) {
        multiplier += 0.02;
    }

    return Math.max(0.85, Math.min(1.15, multiplier));
}

function evidenceMultiplier(txNode) {
    const evidenceText = txNode?.tooltip?.evidence || '';
    const statText = txNode?.tooltip?.stat || '';
    const citationText = txNode?.tooltip?.citation || '';

    const label = evidenceLabelMultiplier(evidenceText);
    const sample = sampleSizeMultiplier(statText);
    const signal = effectSignalMultiplier(evidenceText, statText, citationText);
    const raw = label * sample * signal;
    return Math.max(0.65, Math.min(1.35, raw));
}

function clamp01(value) {
    return Math.max(0, Math.min(1, value));
}

function combineIndependentProtections(parts) {
    let remainingRisk = 1;
    parts.forEach(p => {
        const v = clamp01(p);
        remainingRisk *= (1 - v);
    });
    return 1 - remainingRisk;
}

function buildForwardAdjacency(graphData, interventionNodeMap) {
    const adjacency = new Map();
    graphData.edges.forEach(e => {
        const src = e.data.source;
        const tgt = e.data.target;
        if (e.data.edgeType === 'feedback' || e.data.edgeType === 'protective') return;
        if (interventionNodeMap.has(src)) return;
        if (!adjacency.has(src)) adjacency.set(src, []);
        adjacency.get(src).push(tgt);
    });
    return adjacency;
}

function buildForwardAdjacencyWithMeta(graphData, interventionNodeMap) {
    const adjacency = new Map();
    graphData.edges.forEach(e => {
        const src = e.data.source;
        const tgt = e.data.target;
        const edgeType = e.data.edgeType || 'forward';
        if (edgeType === 'feedback' || edgeType === 'protective') return;
        if (interventionNodeMap.has(src)) return;
        if (!adjacency.has(src)) adjacency.set(src, []);
        adjacency.get(src).push({ target: tgt, edgeType });
    });
    return adjacency;
}

function edgeConfidenceWeight(edgeType) {
    if (edgeType === 'dashed') return 0.7;
    return 1.0;
}

function nodeConfirmationWeight(nodeData) {
    const confirmed = nodeData?.confirmed;
    if (confirmed === 'yes') return 1.0;
    if (confirmed === 'no') return 0.6;
    if (confirmed === 'inactive') return 0.5;
    if (confirmed === 'external') return 0.55;
    return 0.8;
}

function computeNodeLeverage(nonInterventionNodeIds, adjacencyMeta) {
    const leverage = new Map();
    let maxReach = 1;

    nonInterventionNodeIds.forEach(startId => {
        const visited = new Set([startId]);
        const queue = [startId];

        while (queue.length > 0) {
            const nodeId = queue.shift();
            const children = adjacencyMeta.get(nodeId) || [];
            children.forEach(({ target }) => {
                if (!visited.has(target)) {
                    visited.add(target);
                    queue.push(target);
                }
            });
        }

        // Exclude self; this is pure downstream reach.
        const reachCount = Math.max(0, visited.size - 1);
        leverage.set(startId, reachCount);
        if (reachCount > maxReach) maxReach = reachCount;
    });

    // Normalize 0..1
    leverage.forEach((count, nodeId) => {
        leverage.set(nodeId, count / maxReach);
    });

    return leverage;
}

function computeNodeSymptomInfluence(nonInterventionNodeIds, adjacencyMeta, nodeById) {
    const symptomNodeIds = nonInterventionNodeIds.filter(
        nodeId => nodeById.get(nodeId)?.styleClass === 'symptom'
    );
    const totalSymptoms = Math.max(1, symptomNodeIds.length);
    const influence = new Map();

    nonInterventionNodeIds.forEach(startId => {
        const visited = new Set([startId]);
        const queue = [startId];

        while (queue.length > 0) {
            const nodeId = queue.shift();
            const children = adjacencyMeta.get(nodeId) || [];
            children.forEach(({ target }) => {
                if (!visited.has(target)) {
                    visited.add(target);
                    queue.push(target);
                }
            });
        }

        let reachableSymptoms = 0;
        symptomNodeIds.forEach(symptomId => {
            if (symptomId !== startId && visited.has(symptomId)) {
                reachableSymptoms++;
            }
        });
        influence.set(startId, reachableSymptoms / totalSymptoms);
    });

    return influence;
}

function normalizeMetric(metricById) {
    const values = [...metricById.values()];
    if (values.length === 0) return new Map();

    let min = Infinity;
    let max = -Infinity;
    values.forEach(value => {
        min = Math.min(min, value);
        max = Math.max(max, value);
    });

    const out = new Map();
    if (max - min < NUMERIC_EPSILON) {
        metricById.forEach((_, id) => out.set(id, 0.5));
        return out;
    }

    metricById.forEach((value, id) => {
        out.set(id, (value - min) / (max - min));
    });
    return out;
}

// ── Network Impact Scoring (for sidebar ranking) ──

export function computeNetworkImpact(graphData) {
    const maps = buildInterventionMaps(graphData);
    const nodeById = new Map(
        graphData.nodes.map(n => [n.data.id, n.data])
    );
    const nonInterventionNodeIds = graphData.nodes
        .map(n => n.data)
        .filter(d => d.styleClass !== 'intervention')
        .map(d => d.id);

    // Build forward adjacency (exclude feedback/protective/intervention edges)
    const adjacencyMeta = buildForwardAdjacencyWithMeta(graphData, maps.interventionNodeMap);
    const nodeLeverage = computeNodeLeverage(nonInterventionNodeIds, adjacencyMeta);
    const nodeSymptomInfluence = computeNodeSymptomInfluence(nonInterventionNodeIds, adjacencyMeta, nodeById);

    const causalLeverageRawById = new Map();
    const endpointBenefitRawById = new Map();
    const phenotypeRelevanceRawById = new Map();
    const evidenceMultiplierById = new Map();
    const reachableCountById = new Map();

    maps.interventionNodeMap.forEach((txNode, txId) => {
        const targets = maps.interventionTargets.get(txId) || [];
        const bestDecayByNode = new Map();
        const queue = []; // { nodeId, decay }

        // Seed direct targets with full local effect.
        targets.forEach(({ target }) => {
            if ((bestDecayByNode.get(target) || 0) < 1.0) {
                bestDecayByNode.set(target, 1.0);
                queue.push({ nodeId: target, decay: 1.0 });
            }
        });

        // Propagate with decay and edge-confidence penalties; keep strongest path per node.
        while (queue.length > 0) {
            const { nodeId, decay } = queue.shift();
            const children = adjacencyMeta.get(nodeId) || [];
            children.forEach(({ target, edgeType }) => {
                const nextDecay = decay * CASCADE_DECAY * edgeConfidenceWeight(edgeType);
                if (nextDecay < MIN_PROPAGATION_STRENGTH) return;

                const prevBest = bestDecayByNode.get(target) || 0;
                if (nextDecay <= prevBest + NUMERIC_EPSILON) return;

                bestDecayByNode.set(target, nextDecay);
                queue.push({ nodeId: target, decay: nextDecay });
            });
        }

        let causalLeverageRaw = 0;
        let endpointBenefitRaw = 0;
        bestDecayByNode.forEach((decay, nodeId) => {
            const leverage = nodeLeverage.get(nodeId) || 0;
            const confirmationWeight = nodeConfirmationWeight(nodeById.get(nodeId));
            const symptomInfluence = nodeSymptomInfluence.get(nodeId) || 0;

            // Causal leverage emphasizes upstream control potential.
            causalLeverageRaw += decay * ((0.9 * leverage) + 0.1) * confirmationWeight;

            // Endpoint benefit emphasizes downstream symptom influence.
            endpointBenefitRaw += decay * ((0.85 * symptomInfluence) + 0.15) * confirmationWeight;
        });

        const directTargetConfirmation = targets.length > 0
            ? targets.reduce((sum, { target }) => {
                return sum + nodeConfirmationWeight(nodeById.get(target));
            }, 0) / targets.length
            : 0.8;

        causalLeverageRawById.set(txId, causalLeverageRaw);
        endpointBenefitRawById.set(txId, endpointBenefitRaw);
        phenotypeRelevanceRawById.set(txId, directTargetConfirmation);
        evidenceMultiplierById.set(txId, evidenceMultiplier(txNode));
        reachableCountById.set(txId, bestDecayByNode.size);
    });

    const causalLeverageNormById = normalizeMetric(causalLeverageRawById);
    const endpointBenefitNormById = normalizeMetric(endpointBenefitRawById);
    const phenotypeRelevanceNormById = normalizeMetric(phenotypeRelevanceRawById);

    const impact = new Map();
    maps.interventionNodeMap.forEach((_, txId) => {
        const causalLeverageNorm = causalLeverageNormById.get(txId) || 0;
        const endpointBenefitNorm = endpointBenefitNormById.get(txId) || 0;
        const phenotypeRelevanceNorm = phenotypeRelevanceNormById.get(txId) || 0;

        // Hybrid priority:
        // - causal leverage from graph logic
        // - endpoint symptom influence
        // - phenotype relevance from confirmed direct targets
        const graphScore = (
            (0.55 * causalLeverageNorm) +
            (0.30 * endpointBenefitNorm) +
            (0.15 * phenotypeRelevanceNorm)
        );

        const multiplier = evidenceMultiplierById.get(txId) || 1.0;
        const weightedScore = graphScore * multiplier;

        impact.set(txId, {
            score: weightedScore,
            graphScore,
            evidenceMultiplier: multiplier,
            reachableCount: reachableCountById.get(txId) || 0,
            causalLeverage: causalLeverageNorm,
            endpointBenefit: endpointBenefitNorm,
            phenotypeRelevance: phenotypeRelevanceNorm,
        });
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
    const adjacency = buildForwardAdjacency(graphData, maps.interventionNodeMap);

    // Cascade: source-aware propagation from directly defended nodes downstream.
    // For each source node, keep only the strongest path to each downstream node.
    // This prevents split/rejoin topologies from double-counting the same upstream defense.
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

    // BFS queue stores independent source tracks.
    // queue item: { sourceId, nodeId, strength }
    const queue = [];
    const sourceBestStrength = new Map(); // sourceId -> Map(nodeId -> strongest strength)

    directScores.forEach((score, sourceId) => {
        if (score <= 0) return;
        const best = new Map();
        best.set(sourceId, score);
        sourceBestStrength.set(sourceId, best);
        queue.push({ sourceId, nodeId: sourceId, strength: score });
    });

    while (queue.length > 0) {
        const { sourceId, nodeId, strength } = queue.shift();
        const children = adjacency.get(nodeId) || [];
        const best = sourceBestStrength.get(sourceId);
        if (!best) continue;

        children.forEach(childId => {
            const cascaded = strength * CASCADE_DECAY;
            if (cascaded < MIN_PROPAGATION_STRENGTH) return;
            if (!allScores.has(childId)) return;

            const prev = best.get(childId) || 0;
            if (cascaded <= prev + NUMERIC_EPSILON) return;

            best.set(childId, cascaded);
            queue.push({ sourceId, nodeId: childId, strength: cascaded });
        });
    }

    // Combine direct + cascaded source contributions using noisy-OR.
    // This keeps each source bounded while allowing multiple independent sources to help.
    allScores.forEach((entry, nodeId) => {
        const direct = clamp01(directScores.get(nodeId) || 0);
        const parts = [];
        if (direct > 0) parts.push(direct);

        sourceBestStrength.forEach((best, sourceId) => {
            // Skip self-source here to avoid counting direct protection twice.
            if (sourceId === nodeId) return;
            const cascaded = best.get(nodeId) || 0;
            if (cascaded >= MIN_PROPAGATION_STRENGTH) {
                parts.push(cascaded);
            }
        });

        const combined = parts.length > 0 ? combineIndependentProtections(parts) : 0;
        allScores.set(nodeId, { score: combined, isDirect: entry.isDirect });
    });

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
