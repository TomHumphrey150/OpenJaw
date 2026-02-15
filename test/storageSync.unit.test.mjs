import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

const CORE_MODULE_URL = new URL('../public/js/storage/core.js', import.meta.url).href;

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

function createSupabaseMock({ remoteStore = null, remoteUpdatedAt = '2026-01-01T00:00:00.000Z' } = {}) {
    const calls = {
        selects: 0,
        upserts: [],
        deletes: 0,
    };

    const state = {
        remoteStore,
        remoteUpdatedAt,
    };

    return {
        calls,
        state,
        from() {
            return {
                select() {
                    return {
                        eq() {
                            return {
                                async maybeSingle() {
                                    calls.selects += 1;
                                    if (!state.remoteStore) {
                                        return { data: null, error: null };
                                    }
                                    return {
                                        data: {
                                            data: state.remoteStore,
                                            updated_at: state.remoteUpdatedAt,
                                        },
                                        error: null,
                                    };
                                },
                            };
                        },
                    };
                },
                async upsert(payload) {
                    calls.upserts.push(payload);
                    state.remoteStore = payload.data;
                    state.remoteUpdatedAt = payload.updated_at;
                    return { error: null };
                },
                delete() {
                    return {
                        async eq() {
                            calls.deletes += 1;
                            state.remoteStore = null;
                            return { error: null };
                        },
                    };
                },
            };
        },
    };
}

async function importCoreFresh() {
    return import(`${CORE_MODULE_URL}?v=${Date.now()}_${Math.random()}`);
}

beforeEach(() => {
    globalThis.localStorage = createLocalStorageMock();
});

test('initStorageForUser hydrates local cache from remote Supabase row', async () => {
    const remoteStore = {
        version: 1,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings: [],
        dailyCheckIns: { '2026-02-15': ['TX_REMOTE'] },
        hiddenInterventions: [],
        unlockedAchievements: [],
        customCausalDiagram: undefined,
    };
    const supabase = createSupabaseMock({ remoteStore });
    const core = await importCoreFresh();

    await core.initStorageForUser({
        supabaseClient: supabase,
        userId: 'user-123',
    });

    const loaded = core.loadData();
    assert.deepEqual(loaded.dailyCheckIns['2026-02-15'], ['TX_REMOTE']);
    assert.equal(supabase.calls.selects, 1);
});

test('initStorageForUser seeds remote from legacy local store when remote is empty', async () => {
    const core = await importCoreFresh();
    const supabase = createSupabaseMock({ remoteStore: null });

    const legacy = core.createEmptyStore();
    legacy.hiddenInterventions.push('TX_LOCAL');
    globalThis.localStorage.setItem(core.STORAGE_KEY, JSON.stringify(legacy));
    globalThis.localStorage.setItem(`${core.STORAGE_KEY}__updated_at`, new Date().toISOString());

    await core.initStorageForUser({
        supabaseClient: supabase,
        userId: 'user-abc',
    });
    await core.flushRemoteSync();

    assert.equal(supabase.calls.upserts.length >= 1, true);
    assert.equal(supabase.calls.upserts.at(-1).user_id, 'user-abc');
    assert.deepEqual(core.loadData().hiddenInterventions, ['TX_LOCAL']);
});

test('clearData deletes remote row for signed-in users after flush', async () => {
    const core = await importCoreFresh();
    const supabase = createSupabaseMock({ remoteStore: null });

    await core.initStorageForUser({
        supabaseClient: supabase,
        userId: 'user-del',
    });

    const updated = core.loadData();
    updated.unlockedAchievements.push('A1');
    core.saveData(updated);
    await core.flushRemoteSync();

    core.clearData();
    await core.flushRemoteSync();

    assert.equal(supabase.calls.deletes, 1);
});
