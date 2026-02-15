import { initSupabase, signInWithPassword, signUpWithPassword, getCurrentUser } from './auth.js';

function isLocalDevHost(locationObj) {
    return locationObj.hostname === 'localhost' || locationObj.hostname === '127.0.0.1';
}

export async function initLoginPage(overrides = {}) {
    const defaultDocument = typeof document !== 'undefined' ? document : null;
    const defaultLocation = typeof window !== 'undefined'
        ? window.location
        : { hostname: '', search: '', href: '' };

    const deps = {
        documentObj: defaultDocument,
        locationObj: defaultLocation,
        initSupabaseFn: initSupabase,
        signInWithPasswordFn: signInWithPassword,
        signUpWithPasswordFn: signUpWithPassword,
        getCurrentUserFn: getCurrentUser,
        ...overrides,
    };

    const emailInput = deps.documentObj.getElementById('email-input');
    const passwordInput = deps.documentObj.getElementById('password-input');
    const signInButton = deps.documentObj.getElementById('sign-in-btn');
    const createAccountButton = deps.documentObj.getElementById('create-account-btn');
    const loadingEl = deps.documentObj.getElementById('loading');
    const errorEl = deps.documentObj.getElementById('error-message');
    const statusEl = deps.documentObj.getElementById('status-message');
    const supabase = deps.initSupabaseFn();

    function showError(message) {
        errorEl.textContent = message;
        errorEl.style.display = 'block';
        statusEl.style.display = 'none';
        loadingEl.style.display = 'none';
    }

    function showStatus(message) {
        statusEl.textContent = message;
        statusEl.style.display = 'block';
        errorEl.style.display = 'none';
        loadingEl.style.display = 'none';
    }

    function setBusy(busy) {
        emailInput.disabled = busy;
        passwordInput.disabled = busy;
        signInButton.disabled = busy;
        createAccountButton.disabled = busy;
        loadingEl.style.display = busy ? 'block' : 'none';
    }

    function disableAuthControls() {
        signInButton.disabled = true;
        createAccountButton.disabled = true;
        emailInput.disabled = true;
        passwordInput.disabled = true;
    }

    function readCredentials() {
        const email = String(emailInput.value || '').trim();
        const password = String(passwordInput.value || '');
        if (!email || !password) {
            showError('Enter both email and password.');
            return null;
        }
        return { email, password };
    }

    function handleUrlErrorState() {
        const params = new URLSearchParams(deps.locationObj.search || '');
        const errorType = params.get('error');

        if (errorType === 'config') {
            showError('Authentication is not configured. Update /js/config.js with valid Supabase values.');
            disableAuthControls();
        } else if (errorType === 'auth') {
            showError('We could not verify your session. Please sign in again.');
        }
    }

    async function checkAuth() {
        if (!supabase) {
            if (isLocalDevHost(deps.locationObj)) {
                // Local fallback to keep development flow working without Supabase setup
                deps.locationObj.href = '/';
                return;
            }
            showError('Authentication is not configured. Update /js/config.js with valid Supabase values.');
            disableAuthControls();
            return;
        }

        try {
            const user = await deps.getCurrentUserFn();
            if (user) {
                deps.locationObj.href = '/';
            }
        } catch (error) {
            console.error('Failed to check current user:', error);
            showError('Unable to verify login state. Please refresh and try again.');
        }
    }

    handleUrlErrorState();
    await checkAuth();

    signInButton.addEventListener('click', async () => {
        if (!supabase) return;
        const credentials = readCredentials();
        if (!credentials) return;

        statusEl.style.display = 'none';
        errorEl.style.display = 'none';
        setBusy(true);

        const { error: signInError } = await deps.signInWithPasswordFn(credentials.email, credentials.password);
        setBusy(false);
        if (signInError) {
            showError(signInError.message);
            return;
        }

        deps.locationObj.href = '/';
    });

    createAccountButton.addEventListener('click', async () => {
        if (!supabase) return;
        const credentials = readCredentials();
        if (!credentials) return;

        statusEl.style.display = 'none';
        errorEl.style.display = 'none';
        setBusy(true);

        const { data, error: signUpError } = await deps.signUpWithPasswordFn(credentials.email, credentials.password);
        setBusy(false);
        if (signUpError) {
            showError(signUpError.message);
            return;
        }

        if (data?.session) {
            deps.locationObj.href = '/';
            return;
        }

        showStatus('Account created. If email confirmation is enabled, check your inbox before signing in.');
    });
}
