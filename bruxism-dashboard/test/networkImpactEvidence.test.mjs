import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeNetworkImpact } from '../public/js/causalEditor/defenseScoring.js';

function interventionNode(id, evidence) {
    return {
        data: {
            id,
            label: id,
            styleClass: 'intervention',
            tooltip: { evidence },
        },
    };
}

function mechanismNode(id) {
    return {
        data: {
            id,
            label: id,
            styleClass: 'mechanism',
        },
    };
}

function edge(source, target, edgeType = 'forward') {
    return {
        data: {
            source,
            target,
            edgeType,
        },
    };
}

test('network impact is weighted by hard-coded evidence multiplier', () => {
    // Same graph topology for both interventions; only evidence differs.
    const graph = {
        nodes: [
            interventionNode('TX_ROBUST', 'Robust (RCT + meta)'),
            interventionNode('TX_LOW', 'Low (GRADE: extremely low)'),
            mechanismNode('M'),
        ],
        edges: [
            edge('TX_ROBUST', 'M'),
            edge('TX_LOW', 'M'),
        ],
    };

    const impact = computeNetworkImpact(graph);
    const robust = impact.get('TX_ROBUST');
    const low = impact.get('TX_LOW');

    assert.ok(robust, 'missing robust intervention impact');
    assert.ok(low, 'missing low intervention impact');
    assert.equal(robust.graphScore, low.graphScore, 'graph scores should match for identical topology');
    assert.ok(
        robust.score > low.score,
        'robust evidence should produce a higher weighted impact score than low evidence'
    );
    assert.ok(
        robust.evidenceMultiplier > low.evidenceMultiplier,
        'robust evidence should get a higher multiplier than low evidence'
    );
});

test('unknown evidence labels fall back to neutral multiplier', () => {
    const graph = {
        nodes: [
            interventionNode('TX_UNKNOWN', 'Custom internal confidence tag'),
            mechanismNode('M'),
        ],
        edges: [
            edge('TX_UNKNOWN', 'M'),
        ],
    };

    const impact = computeNetworkImpact(graph);
    const result = impact.get('TX_UNKNOWN');

    assert.ok(result, 'missing intervention impact');
    assert.equal(result.score, result.graphScore, 'unknown labels should not alter graph score');
    assert.equal(result.evidenceMultiplier, 1.0);
});
