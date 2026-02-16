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

beforeEach(() => {
    globalThis.localStorage = createLocalStorageMock();
    storage.clearData();
});

test('new protocol arrays are initialized on empty store', () => {
    const data = storage.loadData();
    assert.deepEqual(data.nightExposures, []);
    assert.deepEqual(data.nightOutcomes, []);
    assert.deepEqual(data.morningStates, []);
    assert.deepEqual(data.habitTrials, []);
    assert.deepEqual(data.habitClassifications, []);
});

test('night exposures upsert by night + intervention', () => {
    storage.upsertNightExposure({
        nightId: '2026-02-15',
        interventionId: 'BED_ELEV_TX',
        enabled: true,
        intensity: 0.5,
        tags: ['reflux'],
    });

    storage.upsertNightExposure({
        nightId: '2026-02-15',
        interventionId: 'BED_ELEV_TX',
        enabled: false,
        intensity: 0.2,
        tags: ['adjusted'],
    });

    const exposures = storage.getNightExposures('2026-02-15');
    assert.equal(exposures.length, 1);
    assert.equal(exposures[0].enabled, false);
    assert.equal(exposures[0].intensity, 0.2);
    assert.deepEqual(exposures[0].tags, ['adjusted']);
});

test('night outcomes and morning state upsert by night', () => {
    storage.upsertNightOutcome({
        nightId: '2026-02-14',
        microArousalCount: 12,
        microArousalRatePerHour: 2.4,
    });
    storage.upsertNightOutcome({
        nightId: '2026-02-14',
        microArousalCount: 9,
        confidence: 0.95,
    });

    storage.upsertMorningState({
        nightId: '2026-02-14',
        neckTightness: 7,
        jawSoreness: 4,
    });
    storage.upsertMorningState({
        nightId: '2026-02-14',
        neckTightness: 5,
        earFullness: 3,
    });

    const outcome = storage.getNightOutcome('2026-02-14');
    const morning = storage.getMorningState('2026-02-14');

    assert.equal(outcome.microArousalCount, 9);
    assert.equal(outcome.microArousalRatePerHour, 2.4);
    assert.equal(outcome.confidence, 0.95);
    assert.equal(morning.neckTightness, 5);
    assert.equal(morning.jawSoreness, 4);
    assert.equal(morning.earFullness, 3);
});

test('habit trial lifecycle and classification upsert', () => {
    const trial = storage.startHabitTrial('BED_ELEV_TX', '2026-02-10');
    assert.equal(trial.status, 'active');

    const completed = storage.completeHabitTrial(trial.id, '2026-02-15');
    assert.equal(completed.status, 'completed');
    assert.equal(completed.endNightId, '2026-02-15');

    storage.upsertHabitClassification({
        interventionId: 'BED_ELEV_TX',
        status: 'harmful',
        nightsOn: 6,
        nightsOff: 6,
        microArousalDeltaPct: 18,
        morningStateDelta: 1.3,
        windowQuality: 'clean_one_variable',
    });

    const classification = storage.getHabitClassification('BED_ELEV_TX');
    assert.equal(classification.status, 'harmful');
    assert.equal(classification.nightsOn, 6);
    assert.equal(classification.nightsOff, 6);
    assert.equal(classification.microArousalDeltaPct, 18);
});
