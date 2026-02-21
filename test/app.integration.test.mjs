import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createMockDocument } from './helpers/domMock.mjs';
import { init, setupSignOut } from '../public/js/app.js';

test('init catches auth bootstrap exceptions and shows server error screen', async () => {
    let showLoadingCalls = 0;
    let showServerErrorCalls = 0;
    let checkHealthCalls = 0;

    await init({
        documentObj: createMockDocument([]),
        showLoadingFn: () => { showLoadingCalls += 1; },
        showServerErrorFn: () => { showServerErrorCalls += 1; },
        showAppFn: () => {},
        initSupabaseFn: () => { throw new Error('bad config'); },
        checkAuthAndRedirectFn: async () => true,
        checkServerHealthFn: async () => {
            checkHealthCalls += 1;
            return true;
        },
        fetchFn: async () => ({ ok: true, async json() { return {}; } }),
    });

    assert.equal(showLoadingCalls, 1);
    assert.equal(showServerErrorCalls, 1);
    assert.equal(checkHealthCalls, 0);
});

test('init exits early when auth redirect path is taken', async () => {
    let checkHealthCalls = 0;
    let fetchCalls = 0;

    await init({
        documentObj: createMockDocument([]),
        showLoadingFn: () => {},
        showServerErrorFn: () => {},
        showAppFn: () => {},
        initSupabaseFn: () => {},
        checkAuthAndRedirectFn: async () => false,
        checkServerHealthFn: async () => {
            checkHealthCalls += 1;
            return true;
        },
        fetchFn: async () => {
            fetchCalls += 1;
            return { ok: true, async json() { return {}; } };
        },
    });

    assert.equal(checkHealthCalls, 0);
    assert.equal(fetchCalls, 0);
});

test('setupSignOut handles failed sign-out attempts without throwing', async () => {
    const documentObj = createMockDocument(['sign-out-btn']);
    const signOutBtn = documentObj.getElementById('sign-out-btn');

    let alertMessage = '';
    setupSignOut({
        documentObj,
        confirmFn: () => true,
        signOutFn: async () => {
            throw new Error('temporary auth outage');
        },
        alertFn: (message) => { alertMessage = message; },
    });

    await signOutBtn.trigger('click');

    assert.equal(alertMessage, 'Unable to sign out right now. Please try again.');
});

test('init hydrates storage for the authenticated user before rendering', async () => {
    const documentObj = createMockDocument([
        'disclaimer',
        'data-management-btn',
        'data-modal',
        'close-modal-btn',
        'export-data-btn',
        'import-data-btn',
        'import-file',
        'clear-data-btn',
        'sign-out-btn',
    ]);

    let storageHydrated = 0;
    let graphInitialized = 0;
    let guidedFlowInitialized = 0;
    const storageApi = {
        initStorageForUser: async (args) => {
            storageHydrated += 1;
            assert.equal(args.userId, 'user-42');
            assert.deepEqual(args.supabaseClient, { fake: true });
        },
        downloadExport: () => {},
        importData: () => ({ success: true }),
        clearData: () => {},
        flushRemoteSync: async () => {},
    };

    await init({
        documentObj,
        showLoadingFn: () => {},
        showServerErrorFn: () => {},
        showAppFn: () => {},
        initSupabaseFn: () => {},
        checkAuthAndRedirectFn: async () => true,
        getCurrentUserFn: async () => ({ id: 'user-42' }),
        getSupabaseFn: () => ({ fake: true }),
        checkServerHealthFn: async () => true,
        fetchFn: async (url) => {
            if (url.includes('/api/interventions')) {
                return { ok: true, async json() { return { interventions: [] }; } };
            }
            return { ok: true, async json() { return { disclaimer: 'ok' }; } };
        },
        initCausalEditorFn: () => { graphInitialized += 1; },
        initExperienceFlowFn: ({ storageApi: suppliedStorageApi, documentObj: suppliedDocument }) => {
            guidedFlowInitialized += 1;
            assert.equal(suppliedStorageApi, storageApi);
            assert.equal(suppliedDocument, documentObj);
        },
        storageApi,
        confirmFn: () => false,
    });

    assert.equal(storageHydrated, 1);
    assert.equal(graphInitialized, 1);
    assert.equal(guidedFlowInitialized, 1);
});

test('init backfills canonical graph and rehydrates storage when custom graph is missing', async () => {
    const documentObj = createMockDocument([
        'disclaimer',
        'data-management-btn',
        'data-modal',
        'close-modal-btn',
        'export-data-btn',
        'import-data-btn',
        'import-file',
        'clear-data-btn',
        'sign-out-btn',
    ]);

    let storageHydrated = 0;
    const rpcCalls = [];
    const canonicalPayload = {
        graphData: { nodes: [{ data: { id: 'RMMA' } }], edges: [] },
        lastModified: '2026-02-21T18:00:00.000Z',
    };

    const supabaseClient = {
        rpc: async (fn, params) => {
            rpcCalls.push({ fn, params });
            return { data: true, error: null };
        },
    };

    const storageApi = {
        initStorageForUser: async () => {
            storageHydrated += 1;
        },
        loadData: () => ({ customCausalDiagram: undefined }),
        hasValidCustomDiagram: () => false,
        canonicalGraphPayload: () => canonicalPayload,
        downloadExport: () => {},
        importData: () => ({ success: true }),
        clearData: () => {},
        flushRemoteSync: async () => {},
    };

    await init({
        documentObj,
        showLoadingFn: () => {},
        showServerErrorFn: () => {},
        showAppFn: () => {},
        initSupabaseFn: () => {},
        checkAuthAndRedirectFn: async () => true,
        getCurrentUserFn: async () => ({ id: 'user-42' }),
        getSupabaseFn: () => supabaseClient,
        checkServerHealthFn: async () => true,
        fetchFn: async (url) => {
            if (url.includes('/api/interventions')) {
                return { ok: true, async json() { return { interventions: [] }; } };
            }
            return { ok: true, async json() { return { disclaimer: 'ok' }; } };
        },
        initCausalEditorFn: () => {},
        initExperienceFlowFn: () => {},
        storageApi,
        confirmFn: () => false,
    });

    assert.equal(storageHydrated, 2);
    assert.equal(rpcCalls.length, 1);
    assert.equal(rpcCalls[0].fn, 'backfill_default_graph_if_missing');
    assert.deepEqual(rpcCalls[0].params, {
        graph_data: canonicalPayload.graphData,
        last_modified: canonicalPayload.lastModified,
    });
});

test('init skips canonical graph backfill when custom graph already exists locally', async () => {
    const documentObj = createMockDocument([
        'disclaimer',
        'data-management-btn',
        'data-modal',
        'close-modal-btn',
        'export-data-btn',
        'import-data-btn',
        'import-file',
        'clear-data-btn',
        'sign-out-btn',
    ]);

    let storageHydrated = 0;
    let rpcCalls = 0;
    const supabaseClient = {
        rpc: async () => {
            rpcCalls += 1;
            return { data: true, error: null };
        },
    };

    const storageApi = {
        initStorageForUser: async () => {
            storageHydrated += 1;
        },
        loadData: () => ({
            customCausalDiagram: {
                graphData: {
                    nodes: [],
                    edges: [],
                },
            },
        }),
        hasValidCustomDiagram: () => true,
        canonicalGraphPayload: () => ({
            graphData: { nodes: [], edges: [] },
            lastModified: '2026-02-21T18:00:00.000Z',
        }),
        downloadExport: () => {},
        importData: () => ({ success: true }),
        clearData: () => {},
        flushRemoteSync: async () => {},
    };

    await init({
        documentObj,
        showLoadingFn: () => {},
        showServerErrorFn: () => {},
        showAppFn: () => {},
        initSupabaseFn: () => {},
        checkAuthAndRedirectFn: async () => true,
        getCurrentUserFn: async () => ({ id: 'user-42' }),
        getSupabaseFn: () => supabaseClient,
        checkServerHealthFn: async () => true,
        fetchFn: async (url) => {
            if (url.includes('/api/interventions')) {
                return { ok: true, async json() { return { interventions: [] }; } };
            }
            return { ok: true, async json() { return { disclaimer: 'ok' }; } };
        },
        initCausalEditorFn: () => {},
        initExperienceFlowFn: () => {},
        storageApi,
        confirmFn: () => false,
    });

    assert.equal(storageHydrated, 1);
    assert.equal(rpcCalls, 0);
});
