import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createMockDocument } from './helpers/domMock.mjs';
import { initLoginPage } from '../public/js/login.js';

function createLocation({ hostname = 'app.example.com', search = '' } = {}) {
    return {
        hostname,
        search,
        href: `https://${hostname}/login.html${search}`,
    };
}

function createLoginDom() {
    const documentObj = createMockDocument([
        'email-input',
        'password-input',
        'sign-in-btn',
        'create-account-btn',
        'loading',
        'error-message',
        'status-message',
    ]);
    const emailInput = documentObj.getElementById('email-input');
    const passwordInput = documentObj.getElementById('password-input');
    const signInButton = documentObj.getElementById('sign-in-btn');
    const createAccountButton = documentObj.getElementById('create-account-btn');
    const loadingEl = documentObj.getElementById('loading');
    const errorEl = documentObj.getElementById('error-message');
    const statusEl = documentObj.getElementById('status-message');

    emailInput.value = '';
    passwordInput.value = '';
    loadingEl.style.display = 'none';
    errorEl.style.display = 'none';
    statusEl.style.display = 'none';

    return {
        documentObj,
        emailInput,
        passwordInput,
        signInButton,
        createAccountButton,
        loadingEl,
        errorEl,
        statusEl,
    };
}

test('login page surfaces config error and disables sign-in when ?error=config is present', async () => {
    const { documentObj, signInButton, createAccountButton, emailInput, passwordInput, errorEl } = createLoginDom();
    const locationObj = createLocation({ search: '?error=config' });

    await initLoginPage({
        documentObj,
        locationObj,
        initSupabaseFn: () => null,
        getCurrentUserFn: async () => null,
        signInWithPasswordFn: async () => ({ data: null, error: null }),
        signUpWithPasswordFn: async () => ({ data: null, error: null }),
    });

    assert.equal(signInButton.disabled, true);
    assert.equal(createAccountButton.disabled, true);
    assert.equal(emailInput.disabled, true);
    assert.equal(passwordInput.disabled, true);
    assert.equal(errorEl.style.display, 'block');
    assert.match(errorEl.textContent, /Authentication is not configured/i);
});

test('login page keeps localhost fallback when Supabase is missing', async () => {
    const { documentObj } = createLoginDom();
    const locationObj = createLocation({ hostname: 'localhost' });

    await initLoginPage({
        documentObj,
        locationObj,
        initSupabaseFn: () => null,
        getCurrentUserFn: async () => null,
        signInWithPasswordFn: async () => ({ data: null, error: null }),
        signUpWithPasswordFn: async () => ({ data: null, error: null }),
    });

    assert.equal(locationObj.href, '/');
});

test('login page shows sign-in errors and re-enables controls after failed password sign-in', async () => {
    const { documentObj, emailInput, passwordInput, signInButton, createAccountButton, loadingEl, errorEl } = createLoginDom();
    const locationObj = createLocation();

    emailInput.value = 'user@example.com';
    passwordInput.value = 'bad-password';

    await initLoginPage({
        documentObj,
        locationObj,
        initSupabaseFn: () => ({}),
        getCurrentUserFn: async () => null,
        signInWithPasswordFn: async () => ({ data: null, error: new Error('Invalid login credentials') }),
        signUpWithPasswordFn: async () => ({ data: null, error: null }),
    });

    await signInButton.trigger('click');

    assert.equal(signInButton.disabled, false);
    assert.equal(createAccountButton.disabled, false);
    assert.equal(loadingEl.style.display, 'none');
    assert.equal(errorEl.style.display, 'block');
    assert.equal(errorEl.textContent, 'Invalid login credentials');
});

test('login page shows account-created status when sign-up succeeds without a session', async () => {
    const { documentObj, emailInput, passwordInput, createAccountButton, statusEl, errorEl } = createLoginDom();
    const locationObj = createLocation();

    emailInput.value = 'new@example.com';
    passwordInput.value = 'Password123!';

    await initLoginPage({
        documentObj,
        locationObj,
        initSupabaseFn: () => ({}),
        getCurrentUserFn: async () => null,
        signInWithPasswordFn: async () => ({ data: null, error: null }),
        signUpWithPasswordFn: async () => ({ data: { user: { id: 'u1' }, session: null }, error: null }),
    });

    await createAccountButton.trigger('click');

    assert.equal(errorEl.style.display, 'none');
    assert.equal(statusEl.style.display, 'block');
    assert.match(statusEl.textContent, /account created/i);
});
