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

test('night exposure deletion returns false when record does not exist', () => {
    const deleted = storage.deleteNightExposure('2026-02-10', 'MISSING_TX');
    assert.equal(deleted, false);
});

test('night exposure helpers normalize tags and list all records', () => {
    storage.upsertNightExposure({
        nightId: '2026-02-10',
        interventionId: 'TX_A',
        enabled: true,
        tags: [' valid ', '', 123, 'reflux'],
    });
    storage.upsertNightExposure({
        nightId: '2026-02-11',
        interventionId: 'TX_B',
        enabled: true,
        tags: ['stress'],
    });

    const all = storage.getNightExposures();
    assert.equal(all.length, 2);
    assert.deepEqual(storage.getNightExposure('2026-02-10', 'TX_A').tags, [' valid ', 'reflux']);
});

test('night outcome and morning state upserts preserve previous defined values', () => {
    storage.upsertNightOutcome({
        nightId: '2026-02-10',
        microArousalRatePerHour: 3.2,
        confidence: 0.9,
        source: 'muse',
    });
    storage.upsertNightOutcome({
        nightId: '2026-02-10',
        microArousalCount: 18,
    });

    storage.upsertMorningState({
        nightId: '2026-02-10',
        neckTightness: 7,
        earFullness: 5,
    });
    storage.upsertMorningState({
        nightId: '2026-02-10',
        jawSoreness: 4,
    });

    const outcome = storage.getNightOutcome('2026-02-10');
    const morning = storage.getMorningState('2026-02-10');

    assert.equal(outcome.microArousalRatePerHour, 3.2);
    assert.equal(outcome.confidence, 0.9);
    assert.equal(outcome.source, 'muse');
    assert.equal(outcome.microArousalCount, 18);

    assert.equal(morning.neckTightness, 7);
    assert.equal(morning.earFullness, 5);
    assert.equal(morning.jawSoreness, 4);
});

test('trial completion and abandon return null for unknown trial id', () => {
    assert.equal(storage.completeHabitTrial('missing-id', '2026-02-10'), null);
    assert.equal(storage.abandonHabitTrial('missing-id', '2026-02-10'), null);
});

test('habit classification upsert normalizes invalid status and non-finite counters', () => {
    storage.upsertHabitClassification({
        interventionId: 'TX_STATUS',
        status: 'NOT_A_REAL_STATUS',
        nightsOn: Number.NaN,
        nightsOff: Number.POSITIVE_INFINITY,
        microArousalDeltaPct: Number.NaN,
    });

    const status = storage.getHabitClassification('TX_STATUS');
    assert.equal(status.status, 'unknown');
    assert.equal(status.nightsOn, 0);
    assert.equal(status.nightsOff, 0);
    assert.equal(status.microArousalDeltaPct, undefined);
});

test('habit classification upsert is case-insensitive and replaces existing record', () => {
    storage.upsertHabitClassification({
        interventionId: 'TX_CASE',
        status: 'HARMFUL',
        nightsOn: 5,
        nightsOff: 5,
    });
    const first = storage.getHabitClassification('TX_CASE');
    storage.upsertHabitClassification({
        interventionId: 'TX_CASE',
        status: 'helpful',
        nightsOn: 6,
        nightsOff: 6,
    });
    const second = storage.getHabitClassification('TX_CASE');

    assert.equal(first.status, 'harmful');
    assert.equal(second.status, 'helpful');
    assert.equal(second.nightsOn, 6);
    assert.equal(storage.getHabitClassifications().length, 1);
});
