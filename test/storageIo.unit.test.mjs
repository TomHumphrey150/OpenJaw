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

test('importData hydrates new protocol arrays and remains export-compatible', () => {
    const payload = {
        version: 1,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings: [],
        dailyCheckIns: {},
        nightExposures: [{ nightId: '2026-02-15', interventionId: 'TX_A', enabled: true, createdAt: '2026-02-15T08:00:00.000Z' }],
        nightOutcomes: [{ nightId: '2026-02-15', microArousalRatePerHour: 2.4, createdAt: '2026-02-15T08:00:00.000Z' }],
        morningStates: [{ nightId: '2026-02-15', neckTightness: 4, createdAt: '2026-02-15T08:00:00.000Z' }],
        habitTrials: [{ id: 'trial-1', interventionId: 'TX_A', startNightId: '2026-02-10', status: 'active' }],
        habitClassifications: [{ interventionId: 'TX_A', status: 'neutral', nightsOn: 5, nightsOff: 5, updatedAt: '2026-02-16T08:00:00.000Z' }],
        hiddenInterventions: [],
        unlockedAchievements: [],
    };

    const result = storage.importData(JSON.stringify(payload));
    assert.equal(result.success, true);

    const loaded = storage.loadData();
    assert.equal(loaded.nightExposures.length, 1);
    assert.equal(loaded.nightOutcomes.length, 1);
    assert.equal(loaded.morningStates.length, 1);
    assert.equal(loaded.habitTrials.length, 1);
    assert.equal(loaded.habitClassifications.length, 1);

    const exported = JSON.parse(storage.exportData());
    assert.equal(Array.isArray(exported.nightExposures), true);
    assert.equal(Array.isArray(exported.nightOutcomes), true);
    assert.equal(Array.isArray(exported.morningStates), true);
    assert.equal(Array.isArray(exported.habitTrials), true);
    assert.equal(Array.isArray(exported.habitClassifications), true);
});

test('importData defaults missing protocol arrays to empty lists', () => {
    const result = storage.importData(JSON.stringify({
        version: 1,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings: [],
        dailyCheckIns: {},
        hiddenInterventions: [],
        unlockedAchievements: [],
    }));

    assert.equal(result.success, true);
    const loaded = storage.loadData();
    assert.deepEqual(loaded.nightExposures, []);
    assert.deepEqual(loaded.nightOutcomes, []);
    assert.deepEqual(loaded.morningStates, []);
    assert.deepEqual(loaded.habitTrials, []);
    assert.deepEqual(loaded.habitClassifications, []);
});
