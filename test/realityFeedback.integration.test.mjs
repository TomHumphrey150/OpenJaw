import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import * as storage from '../public/js/storage.js';
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

function dayKey(dayOffset) {
    const date = new Date();
    date.setDate(date.getDate() - dayOffset);
    return date.toISOString().split('T')[0];
}

function interventionNode(id) {
    return { data: { id, label: id, styleClass: 'intervention' } };
}

function mechanismNode(id) {
    return { data: { id, label: id, styleClass: 'mechanism' } };
}

function edge(source, target) {
    return { data: { source, target, edgeType: 'forward' } };
}

function approxEqual(actual, expected, epsilon = 1e-9) {
    assert.ok(
        Math.abs(actual - expected) < epsilon,
        `expected ${expected}, got ${actual}`
    );
}

function setOutcomeAndMorning(date, microRate, morningLevel) {
    storage.upsertNightOutcome({
        nightId: date,
        microArousalRatePerHour: microRate,
    });
    storage.upsertMorningState({
        nightId: date,
        globalSensation: morningLevel,
        neckTightness: morningLevel,
        jawSoreness: morningLevel,
        earFullness: morningLevel,
    });
}

beforeEach(() => {
    globalThis.localStorage = createLocalStorageMock();
    storage.clearData();
});

test('end-to-end: harmful personal evidence downranks intervention even with high static rating', () => {
    // Check-in behavior says it is being used every day.
    for (let i = 0; i < 7; i += 1) {
        storage.toggleCheckIn(dayKey(i), 'BED_ELEV_TX');
    }
    storage.setRating('BED_ELEV_TX', 'highly_effective');

    // OFF baseline nights
    for (let i = 7; i < 12; i += 1) {
        setOutcomeAndMorning(dayKey(i), 2.0, 3.0);
    }
    // ON nights worsen (one-variable clean)
    for (let i = 0; i < 5; i += 1) {
        const d = dayKey(i);
        setOutcomeAndMorning(d, 3.0, 5.0);
        storage.upsertNightExposure({
            nightId: d,
            interventionId: 'BED_ELEV_TX',
            enabled: true,
        });
    }

    const [classification] = storage.recomputeHabitClassifications();
    assert.equal(classification.interventionId, 'BED_ELEV_TX');
    assert.equal(classification.status, 'harmful');

    const graph = {
        nodes: [interventionNode('BED_ELEV_TX'), mechanismNode('A')],
        edges: [edge('BED_ELEV_TX', 'A')],
    };
    const scores = computeDefenseScores(graph);

    // harmful class (0.15) * 7/7 active
    approxEqual(scores.get('A').score, 0.15);
});

test('end-to-end: helpful personal evidence can up-rank beyond low static rating', () => {
    for (let i = 0; i < 7; i += 1) {
        storage.toggleCheckIn(dayKey(i), 'JAW_RELAX_TX');
    }
    storage.setRating('JAW_RELAX_TX', 'ineffective');

    // OFF baseline
    for (let i = 7; i < 12; i += 1) {
        setOutcomeAndMorning(dayKey(i), 4.0, 4.0);
    }
    // ON improves
    for (let i = 0; i < 5; i += 1) {
        const d = dayKey(i);
        setOutcomeAndMorning(d, 3.0, 3.5);
        storage.upsertNightExposure({
            nightId: d,
            interventionId: 'JAW_RELAX_TX',
            enabled: true,
        });
    }

    const [classification] = storage.recomputeHabitClassifications();
    assert.equal(classification.status, 'helpful');

    const graph = {
        nodes: [interventionNode('JAW_RELAX_TX'), mechanismNode('A')],
        edges: [edge('JAW_RELAX_TX', 'A')],
    };
    const scores = computeDefenseScores(graph);

    // helpful class (1.0) * 7/7 active
    approxEqual(scores.get('A').score, 1.0);
});
