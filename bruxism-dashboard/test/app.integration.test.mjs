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
