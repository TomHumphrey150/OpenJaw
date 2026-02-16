import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import * as storage from '../public/js/storage.js';

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

function nightId(offset) {
    const date = new Date('2026-02-01T00:00:00.000Z');
    date.setDate(date.getDate() + offset);
    return date.toISOString().split('T')[0];
}

function setNightOutcomeAndMorning(offset, microRate, morning) {
    storage.upsertNightOutcome({
        nightId: nightId(offset),
        microArousalRatePerHour: microRate,
    });
    storage.upsertMorningState({
        nightId: nightId(offset),
        globalSensation: morning,
        neckTightness: morning,
        jawSoreness: morning,
        earFullness: morning,
    });
}

beforeEach(() => {
    globalThis.localStorage = createLocalStorageMock();
    storage.clearData();
});

test('recompute marks habit harmful when micro-arousals and morning load worsen', () => {
    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 2.0, 3.0); // OFF baseline
    }
    for (let i = 5; i < 10; i += 1) {
        const id = nightId(i);
        setNightOutcomeAndMorning(i, 3.0, 5.0); // ON worsens
        storage.upsertNightExposure({
            nightId: id,
            interventionId: 'BED_ELEV_TX',
            enabled: true,
        });
    }

    const classifications = storage.recomputeHabitClassifications();
    const bed = classifications.find(c => c.interventionId === 'BED_ELEV_TX');

    assert.equal(bed.status, 'harmful');
    assert.equal(bed.nightsOn, 5);
    assert.equal(bed.nightsOff, 5);
    assert.equal(bed.windowQuality, 'clean_one_variable');
    assert.equal(bed.microArousalDeltaPct, 50);
    assert.equal(bed.morningStateDelta, 2);
});

test('recompute marks habit helpful when micro-arousals improve without morning penalty', () => {
    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 5.0, 5.0); // OFF baseline
    }
    for (let i = 5; i < 10; i += 1) {
        const id = nightId(i);
        setNightOutcomeAndMorning(i, 3.5, 4.0); // ON improves
        storage.upsertNightExposure({
            nightId: id,
            interventionId: 'JAW_RELAX_TX',
            enabled: true,
        });
    }

    const classifications = storage.recomputeHabitClassifications();
    const tx = classifications.find(c => c.interventionId === 'JAW_RELAX_TX');

    assert.equal(tx.status, 'helpful');
    assert.equal(tx.nightsOn, 5);
    assert.equal(tx.nightsOff, 5);
    assert.equal(tx.microArousalDeltaPct, -30);
});

test('recompute marks intervention unknown when clean one-variable evidence is insufficient', () => {
    for (let i = 0; i < 10; i += 1) {
        setNightOutcomeAndMorning(i, 4.0, 4.0);
    }

    for (let i = 7; i < 10; i += 1) {
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'PILLOW_STACK_TX',
            enabled: true,
        });
    }

    const classifications = storage.recomputeHabitClassifications();
    const tx = classifications.find(c => c.interventionId === 'PILLOW_STACK_TX');

    assert.equal(tx.status, 'unknown');
    assert.equal(tx.nightsOn, 3);
    assert.equal(tx.nightsOff, 7);
    assert.equal(tx.windowQuality, 'insufficient_data');
});

test('recompute marks intervention neutral when objective change is inside thresholds', () => {
    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 4.0, 4.0); // OFF
    }
    for (let i = 5; i < 10; i += 1) {
        setNightOutcomeAndMorning(i, 4.2, 4.1); // ON (+5%)
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'NEUTRAL_TX',
            enabled: true,
        });
    }

    const tx = storage.recomputeHabitClassifications().find(c => c.interventionId === 'NEUTRAL_TX');
    assert.equal(tx.status, 'neutral');
    assert.equal(tx.microArousalDeltaPct, 5);
});

test('morning safety worsening can mark harmful even when micro-arousal objective improves', () => {
    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 4.0, 3.0); // OFF
    }
    for (let i = 5; i < 10; i += 1) {
        setNightOutcomeAndMorning(i, 3.0, 5.0); // ON objective improves, symptoms worsen
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'SAFETY_TX',
            enabled: true,
        });
    }

    const tx = storage.recomputeHabitClassifications().find(c => c.interventionId === 'SAFETY_TX');
    assert.equal(tx.status, 'harmful');
    assert.equal(tx.microArousalDeltaPct, -25);
    assert.equal(tx.morningStateDelta, 2);
});

test('classification thresholds are inclusive at +/-10 percent', () => {
    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 10.0, 4.0); // OFF shared baseline
    }

    for (let i = 5; i < 10; i += 1) {
        setNightOutcomeAndMorning(i, 9.0, 4.0); // -10%
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'BOUND_HELPFUL_TX',
            enabled: true,
        });
    }
    const helpful = storage.recomputeHabitClassifications().find(c => c.interventionId === 'BOUND_HELPFUL_TX');
    assert.equal(helpful.status, 'helpful');
    assert.equal(helpful.microArousalDeltaPct, -10);

    storage.clearData();

    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 10.0, 4.0);
    }
    for (let i = 5; i < 10; i += 1) {
        setNightOutcomeAndMorning(i, 11.0, 4.0); // +10%
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'BOUND_HARMFUL_TX',
            enabled: true,
        });
    }
    const harmful = storage.recomputeHabitClassifications().find(c => c.interventionId === 'BOUND_HARMFUL_TX');
    assert.equal(harmful.status, 'harmful');
    assert.equal(harmful.microArousalDeltaPct, 10);
});

test('confounded nights are excluded from computation and quality is marked confounded when enough clean data exists', () => {
    // OFF nights
    for (let i = 0; i < 5; i += 1) {
        setNightOutcomeAndMorning(i, 4.0, 4.0);
    }

    // Clean ON nights for target intervention
    for (let i = 5; i < 10; i += 1) {
        setNightOutcomeAndMorning(i, 5.0, 5.0);
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'TARGET_TX',
            enabled: true,
        });
    }

    // Confounded nights (should be ignored in ON/OFF means)
    for (let i = 10; i < 13; i += 1) {
        setNightOutcomeAndMorning(i, 2.0, 2.0);
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'TARGET_TX',
            enabled: true,
        });
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'OTHER_TX',
            enabled: true,
        });
    }

    const target = storage.recomputeHabitClassifications().find(c => c.interventionId === 'TARGET_TX');
    assert.equal(target.nightsOn, 5, 'only clean ON nights should count');
    assert.equal(target.nightsOff, 5, 'only clean OFF nights should count');
    assert.equal(target.microArousalDeltaPct, 25, 'confounded low-outcome nights must not dilute effect');
    assert.equal(target.windowQuality, 'confounded');
});

test('classifier uses micro-arousal count fallback when rate is missing', () => {
    for (let i = 0; i < 5; i += 1) {
        storage.upsertNightOutcome({
            nightId: nightId(i),
            microArousalCount: 20,
        });
    }
    for (let i = 5; i < 10; i += 1) {
        storage.upsertNightOutcome({
            nightId: nightId(i),
            microArousalCount: 30,
        });
        storage.upsertNightExposure({
            nightId: nightId(i),
            interventionId: 'COUNT_ONLY_TX',
            enabled: true,
        });
    }

    const tx = storage.recomputeHabitClassifications().find(c => c.interventionId === 'COUNT_ONLY_TX');
    assert.equal(tx.status, 'harmful');
    assert.equal(tx.microArousalDeltaPct, 50);
});
