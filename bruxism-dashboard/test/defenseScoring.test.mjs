import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import * as storage from '../public/js/storage.js';
import { CASCADE_DECAY } from '../public/js/causalEditor/defenseConstants.js';
import { computeDefenseScores } from '../public/js/causalEditor/defenseScoring.js';

function createLocalStorageMock() {
    const values = new Map();
    return {
        getItem(key) {
            return values.has(key) ? values.get(key) : null;
        },
        setItem(key, value) {
            values.set(key, String(value));
        },
        removeItem(key) {
            values.delete(key);
        },
        clear() {
            values.clear();
        },
    };
}

function approxEqual(actual, expected, message) {
    const delta = Math.abs(actual - expected);
    assert.ok(
        delta < 1e-9,
        `${message}: expected ${expected}, got ${actual} (delta=${delta})`
    );
}

function interventionNode(id) {
    return {
        data: {
            id,
            label: id,
            styleClass: 'intervention',
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

function daysAgoKey(daysAgo) {
    const date = new Date();
    date.setDate(date.getDate() - daysAgo);
    return date.toISOString().split('T')[0];
}

function activateInterventionForLast7Days(interventionId, effectiveness = 'ineffective') {
    storage.setRating(interventionId, effectiveness);
    for (let i = 0; i < 7; i += 1) {
        storage.toggleCheckIn(daysAgoKey(i), interventionId);
    }
}

beforeEach(() => {
    globalThis.localStorage = createLocalStorageMock();
    storage.clearData();
});

test('split then rejoin does not amplify a single upstream defense source', () => {
    activateInterventionForLast7Days('TX_A', 'ineffective');

    const graph = {
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
    };

    const scores = computeDefenseScores(graph);

    const root = 0.1; // ineffective * 7/7
    const oneHop = root * CASCADE_DECAY;
    const twoHops = oneHop * CASCADE_DECAY;

    approxEqual(scores.get('A').score, root, 'direct target keeps direct score');
    approxEqual(scores.get('B').score, oneHop, 'one-hop branch B decays once');
    approxEqual(scores.get('C').score, oneHop, 'one-hop branch C decays once');
    approxEqual(scores.get('D').score, twoHops, 'rejoined node uses strongest single-source path only');

    assert.ok(
        scores.get('D').score <= scores.get('A').score,
        'a single source cannot produce more downstream protection than at its origin'
    );
});

test('multiple paths from the same source use best path only, not path-sum', () => {
    activateInterventionForLast7Days('TX_A', 'ineffective');

    const graph = {
        nodes: [
            interventionNode('TX_A'),
            mechanismNode('A'),
            mechanismNode('X'),
            mechanismNode('B'),
        ],
        edges: [
            edge('TX_A', 'A'),
            edge('A', 'B'),      // 1 hop from A
            edge('A', 'X'),
            edge('X', 'B'),      // 2 hops from A
        ],
    };

    const scores = computeDefenseScores(graph);

    const expectedBestPath = 0.1 * CASCADE_DECAY; // 0.08
    approxEqual(
        scores.get('B').score,
        expectedBestPath,
        'node B should take best (shortest/strongest) path from same source'
    );
});

test('independent upstream sources combine at convergence without topological double-counting', () => {
    activateInterventionForLast7Days('TX_A', 'ineffective');
    activateInterventionForLast7Days('TX_B', 'ineffective');

    const graph = {
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
    };

    const scores = computeDefenseScores(graph);

    const fromA = 0.1 * CASCADE_DECAY;
    const fromB = 0.1 * CASCADE_DECAY;
    const expectedCombined = 1 - (1 - fromA) * (1 - fromB); // noisy-OR

    approxEqual(
        scores.get('C').score,
        expectedCombined,
        'converged node should combine independent sources without additive path inflation'
    );

    assert.ok(scores.get('C').score > fromA, 'independent sources can improve coverage');
    assert.ok(scores.get('C').score < fromA + fromB, 'combined coverage is bounded below pure addition');
});

test('feedback and protective edges are excluded from defensive forward propagation', () => {
    activateInterventionForLast7Days('TX_A', 'ineffective');

    const graph = {
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
    };

    const scores = computeDefenseScores(graph);

    approxEqual(scores.get('A').score, 0.1, 'direct target still receives direct protection');
    approxEqual(scores.get('B').score, 0, 'feedback edge is ignored for forward defense cascade');
    approxEqual(scores.get('C').score, 0, 'protective edge is ignored for forward defense cascade');
});
