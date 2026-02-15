import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

const AUTH_MODULE_URL = new URL('../public/js/auth.js', import.meta.url).href;

function createLocation({ hostname = 'app.example.com', search = '' } = {}) {
    const origin = hostname.startsWith('http') ? hostname : `https://${hostname}`;
    return {
        hostname,
        origin,
        search,
        href: `${origin}/`,
    };
}

function setupWindow({
    hostname,
    search = '',
    supabaseUrl = '',
    supabasePublishableKey = '',
    supabaseAnonKey = '',
    createClientImpl = null,
} = {}) {
    const location = createLocation({ hostname, search });
    const effectiveKey = supabasePublishableKey || supabaseAnonKey;
    const windowObj = {
        location,
        SUPABASE_URL: supabaseUrl,
        SUPABASE_PUBLISHABLE_KEY: effectiveKey,
        SUPABASE_ANON_KEY: effectiveKey,
        supabase: createClientImpl
            ? { createClient: createClientImpl }
            : { createClient: () => ({ auth: {} }) },
    };
    globalThis.window = windowObj;
    return windowObj;
}

async function importAuthFresh() {
    return import(`${AUTH_MODULE_URL}?v=${Date.now()}_${Math.random()}`);
}

beforeEach(() => {
    delete globalThis.window;
});

test('checkAuthAndRedirect blocks deployed environments when Supabase is not configured', async () => {
    const windowObj = setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'YOUR_SUPABASE_URL',
        supabasePublishableKey: 'YOUR_SUPABASE_PUBLISHABLE_KEY',
    });
    const auth = await importAuthFresh();

    const client = auth.initSupabase();
    assert.equal(client, null);

    const allowed = await auth.checkAuthAndRedirect();
    assert.equal(allowed, false);
    assert.equal(windowObj.location.href, '/login.html?error=config');
});

test('checkAuthAndRedirect allows localhost when Supabase is not configured', async () => {
    setupWindow({
        hostname: 'localhost',
        supabaseUrl: '',
        supabasePublishableKey: '',
    });
    const auth = await importAuthFresh();

    auth.initSupabase();
    const allowed = await auth.checkAuthAndRedirect();
    assert.equal(allowed, true);
});

test('checkAuthAndRedirect redirects to login when no authenticated user exists', async () => {
    const windowObj = setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        createClientImpl: () => ({
            auth: {
                async getUser() {
                    return { data: { user: null }, error: null };
                },
            },
        }),
    });
    const auth = await importAuthFresh();

    const client = auth.initSupabase();
    assert.ok(client, 'expected Supabase client to initialize');

    const allowed = await auth.checkAuthAndRedirect();
    assert.equal(allowed, false);
    assert.equal(windowObj.location.href, '/login.html');
});

test('checkAuthAndRedirect handles auth API errors with explicit error redirect', async () => {
    const windowObj = setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        createClientImpl: () => ({
            auth: {
                async getUser() {
                    return { data: { user: null }, error: new Error('token refresh failed') };
                },
            },
        }),
    });
    const auth = await importAuthFresh();
    auth.initSupabase();

    const allowed = await auth.checkAuthAndRedirect();
    assert.equal(allowed, false);
    assert.equal(windowObj.location.href, '/login.html?error=auth');
});

test('signOut redirects to login even when provider signOut fails', async () => {
    const windowObj = setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        createClientImpl: () => ({
            auth: {
                async signOut() {
                    return { error: new Error('network error') };
                },
            },
        }),
    });
    const auth = await importAuthFresh();
    auth.initSupabase();

    await auth.signOut();
    assert.equal(windowObj.location.href, '/login.html');
});

test('signInWithPassword validates required credentials', async () => {
    setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        createClientImpl: () => ({
            auth: {
                async signInWithPassword() {
                    return { data: null, error: null };
                },
            },
        }),
    });
    const auth = await importAuthFresh();
    auth.initSupabase();

    const result = await auth.signInWithPassword('', '');
    assert.ok(result.error);
    assert.match(result.error.message, /required/i);
});

test('signInWithPassword uses normalized email and password', async () => {
    let payload = null;
    setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        createClientImpl: () => ({
            auth: {
                async signInWithPassword(args) {
                    payload = args;
                    return { data: { session: { access_token: 'abc' } }, error: null };
                },
            },
        }),
    });
    const auth = await importAuthFresh();
    auth.initSupabase();

    const result = await auth.signInWithPassword('  USER@Example.COM ', 'Secret123!');
    assert.equal(result.error, null);
    assert.deepEqual(payload, {
        email: 'user@example.com',
        password: 'Secret123!',
    });
});

test('signUpWithPassword uses normalized email and password', async () => {
    let payload = null;
    setupWindow({
        hostname: 'app.example.com',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        createClientImpl: () => ({
            auth: {
                async signUp(args) {
                    payload = args;
                    return { data: { user: { id: 'u1' }, session: null }, error: null };
                },
            },
        }),
    });
    const auth = await importAuthFresh();
    auth.initSupabase();

    const result = await auth.signUpWithPassword('  NEW@Example.COM ', 'Password1!');
    assert.equal(result.error, null);
    assert.deepEqual(payload, {
        email: 'new@example.com',
        password: 'Password1!',
    });
});
