import { checkServerHealth, showServerError, showLoading, showApp } from './serverCheck.js';
import { initCausalEditor } from './causalEditor.js';
import * as storage from './storage.js';
import { initSupabase, checkAuthAndRedirect, signOut } from './auth.js';

const runtimeDocument = typeof document !== 'undefined' ? document : null;
const runtimeWindow = typeof window !== 'undefined' ? window : null;

const defaultDeps = {
    checkServerHealthFn: checkServerHealth,
    showServerErrorFn: showServerError,
    showLoadingFn: showLoading,
    showAppFn: showApp,
    initCausalEditorFn: initCausalEditor,
    storageApi: storage,
    initSupabaseFn: initSupabase,
    checkAuthAndRedirectFn: checkAuthAndRedirect,
    signOutFn: signOut,
    fetchFn: (...args) => fetch(...args),
    alertFn: (message) => alert(message),
    confirmFn: (message) => confirm(message),
    reloadFn: () => runtimeWindow?.location?.reload?.(),
    documentObj: runtimeDocument,
};

export async function init(overrides = {}) {
    const deps = { ...defaultDeps, ...overrides };
    deps.showLoadingFn();

    try {
        // Initialize Supabase and check auth
        deps.initSupabaseFn();
        const isAuthed = await deps.checkAuthAndRedirectFn();
        if (!isAuthed) return; // Will redirect to login

        const serverOk = await deps.checkServerHealthFn();
        if (!serverOk) {
            deps.showServerErrorFn();
            return;
        }

        const [interventionsRes, infoRes] = await Promise.all([
            deps.fetchFn('/api/interventions'),
            deps.fetchFn('/api/bruxism-info')
        ]);

        if (!interventionsRes.ok || !infoRes.ok) {
            throw new Error('Failed to fetch data');
        }

        const interventionsData = await interventionsRes.json();
        const bruxismInfoData = await infoRes.json();

        deps.showAppFn();

        // Set disclaimer
        const disclaimerEl = deps.documentObj.getElementById('disclaimer');
        if (disclaimerEl && bruxismInfoData.disclaimer) {
            disclaimerEl.textContent = bruxismInfoData.disclaimer;
        }

        // Initialize causal graph + defense check-in
        deps.initCausalEditorFn(interventionsData.interventions);

        // Data management modal
        setupDataManagement(deps);

        // Sign out button
        setupSignOut(deps);

    } catch (error) {
        console.error('Failed to load data:', error);
        deps.showServerErrorFn();
    }
}

export function setupDataManagement(overrides = {}) {
    const deps = { ...defaultDeps, ...overrides };
    const dataBtn = deps.documentObj.getElementById('data-management-btn');
    const modal = deps.documentObj.getElementById('data-modal');
    const closeBtn = deps.documentObj.getElementById('close-modal-btn');
    const exportBtn = deps.documentObj.getElementById('export-data-btn');
    const importBtn = deps.documentObj.getElementById('import-data-btn');
    const importInput = deps.documentObj.getElementById('import-file');
    const clearBtn = deps.documentObj.getElementById('clear-data-btn');

    dataBtn.addEventListener('click', () => modal.classList.remove('hidden'));
    closeBtn.addEventListener('click', () => modal.classList.add('hidden'));
    modal.addEventListener('click', (e) => {
        if (e.target === modal) modal.classList.add('hidden');
    });

    exportBtn.addEventListener('click', () => deps.storageApi.downloadExport());

    importBtn.addEventListener('click', () => importInput.click());
    importInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        try {
            const text = await file.text();
            const result = deps.storageApi.importData(text);
            if (result.success) {
                deps.alertFn('Data imported successfully! Reloading...');
                deps.reloadFn();
            } else {
                deps.alertFn('Invalid data format: ' + (result.errors ? result.errors.join(', ') : 'Unknown error'));
            }
        } catch (err) {
            deps.alertFn('Error reading file: ' + err.message);
        }
        importInput.value = '';
        modal.classList.add('hidden');
    });

    clearBtn.addEventListener('click', () => {
        if (deps.confirmFn('Are you sure you want to clear all personal data? This cannot be undone.')) {
            deps.storageApi.clearData();
            deps.alertFn('All personal data has been cleared.');
            modal.classList.add('hidden');
            deps.reloadFn();
        }
    });
}

export function setupSignOut(overrides = {}) {
    const deps = { ...defaultDeps, ...overrides };
    const signOutBtn = deps.documentObj.getElementById('sign-out-btn');
    if (signOutBtn) {
        signOutBtn.addEventListener('click', async () => {
            if (deps.confirmFn('Sign out?')) {
                try {
                    await deps.signOutFn();
                } catch (error) {
                    console.error('Sign-out failed:', error);
                    deps.alertFn('Unable to sign out right now. Please try again.');
                }
            }
        });
    }
}

if (runtimeDocument) {
    runtimeDocument.addEventListener('DOMContentLoaded', () => {
        void init();
    });
}
