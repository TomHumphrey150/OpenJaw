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

function todayKey() {
    return new Date().toISOString().split('T')[0];
}

beforeEach(() => {
    globalThis.localStorage = createLocalStorageMock();
    storage.clearData();
});

test('clearData removes check-ins immediately without requiring reload', () => {
    storage.toggleCheckIn(todayKey(), 'TX_A');

    const before = storage.getCheckInsRange(7);
    assert.equal(
        Object.values(before).some(ids => ids.includes('TX_A')),
        true,
        'sanity check: check-in exists before clear'
    );

    storage.clearData();

    const after = storage.getCheckInsRange(7);
    assert.equal(
        Object.values(after).some(ids => ids.includes('TX_A')),
        false,
        'check-in should be gone after clearData()'
    );
});

test('loadData returns isolated empty stores when storage is empty', () => {
    const first = storage.loadData();
    first.dailyCheckIns['2099-01-01'] = ['TX_B'];
    first.hiddenInterventions.push('TX_B');

    const second = storage.loadData();
    assert.equal(second.dailyCheckIns['2099-01-01'], undefined);
    assert.deepEqual(second.hiddenInterventions, []);
});
