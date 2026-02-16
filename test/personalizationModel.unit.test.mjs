import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeHabitClassifications } from '../public/js/storage/personalization.js';

function buildNight(nightId, {
    interventionId = null,
    microRate = undefined,
    microCount = undefined,
    morning = undefined,
} = {}) {
    const exposure = interventionId
        ? { nightId, interventionId, enabled: true, createdAt: `${nightId}T08:00:00.000Z` }
        : null;
    const outcome = {
        nightId,
        microArousalRatePerHour: microRate,
        microArousalCount: microCount,
        createdAt: `${nightId}T08:00:00.000Z`,
    };
    const state = morning === undefined
        ? null
        : {
            nightId,
            globalSensation: morning,
            neckTightness: morning,
            jawSoreness: morning,
            earFullness: morning,
            createdAt: `${nightId}T08:00:00.000Z`,
        };

    return { exposure, outcome, state };
}

test('objective anchor uses micro-arousal rate before count when both are present', () => {
    const nightExposures = [];
    const nightOutcomes = [];

    for (let i = 1; i <= 5; i += 1) {
        const n = buildNight(`2026-02-0${i}`, { microRate: 2, microCount: 100 });
        nightOutcomes.push(n.outcome);
    }
    for (let i = 6; i <= 10; i += 1) {
        const n = buildNight(`2026-02-${i}`, {
            interventionId: 'TX_RATE_ANCHOR',
            microRate: 4,
            microCount: 1, // would suggest improvement if count were used
        });
        nightExposures.push(n.exposure);
        nightOutcomes.push(n.outcome);
    }

    const [tx] = computeHabitClassifications({ nightExposures, nightOutcomes, morningStates: [] });
    assert.equal(tx.interventionId, 'TX_RATE_ANCHOR');
    assert.equal(tx.status, 'harmful');
    assert.equal(tx.microArousalDeltaPct, 100);
});

test('classifier remains unknown when OFF baseline objective is zero (no unstable divide behavior)', () => {
    const nightExposures = [];
    const nightOutcomes = [];

    for (let i = 1; i <= 5; i += 1) {
        nightOutcomes.push(buildNight(`2026-03-0${i}`, { microRate: 0 }).outcome);
    }
    for (let i = 6; i <= 10; i += 1) {
        const n = buildNight(`2026-03-${i}`, {
            interventionId: 'TX_ZERO_BASE',
            microRate: 1,
        });
        nightExposures.push(n.exposure);
        nightOutcomes.push(n.outcome);
    }

    const [tx] = computeHabitClassifications({ nightExposures, nightOutcomes, morningStates: [] });
    assert.equal(tx.status, 'unknown');
    assert.equal(tx.microArousalDeltaPct, undefined);
    assert.equal(tx.windowQuality, 'clean_one_variable');
});

test('output order is deterministic and sorted by intervention id', () => {
    const nightExposures = [];
    const nightOutcomes = [];
    const morningStates = [];

    // Shared OFF nights
    for (let i = 1; i <= 5; i += 1) {
        const n = buildNight(`2026-04-0${i}`, { microRate: 4, morning: 4 });
        nightOutcomes.push(n.outcome);
        morningStates.push(n.state);
    }
    // TX_B ON nights
    for (let i = 6; i <= 10; i += 1) {
        const n = buildNight(`2026-04-${i}`, { interventionId: 'TX_B', microRate: 4.4, morning: 4.1 });
        nightExposures.push(n.exposure);
        nightOutcomes.push(n.outcome);
        morningStates.push(n.state);
    }
    // TX_A ON nights
    for (let i = 11; i <= 15; i += 1) {
        const n = buildNight(`2026-04-${i}`, { interventionId: 'TX_A', microRate: 3.6, morning: 3.9 });
        nightExposures.push(n.exposure);
        nightOutcomes.push(n.outcome);
        morningStates.push(n.state);
    }

    const classifications = computeHabitClassifications({ nightExposures, nightOutcomes, morningStates });
    assert.deepEqual(classifications.map(c => c.interventionId), ['TX_A', 'TX_B']);
});
