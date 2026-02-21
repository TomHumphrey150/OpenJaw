/**
 * Shared storage core utilities.
 *
 * The public storage API remains synchronous for UI simplicity.
 * This module keeps an in-memory store, writes to localStorage, and syncs
 * to Supabase in the background when a signed-in user is available.
 */

export const STORAGE_KEY = 'bruxism_personal_data';
export const STORAGE_VERSION = 1;

// Simple V1 experimentation protocol defaults.
// Phase 1 only defines these constants; behavior wiring comes later phases.
export const SIMPLE_EXPERIMENT_PROTOCOL = Object.freeze({
    oneVariableAtATime: true,
    minNightsOn: 5,
    minNightsOff: 5,
    helpfulThresholdPct: -10,
    harmfulThresholdPct: 10,
    morningWorseThreshold: 1,
});

export const HABIT_STATUS = Object.freeze({
    HELPFUL: 'helpful',
    NEUTRAL: 'neutral',
    HARMFUL: 'harmful',
    UNKNOWN: 'unknown',
});

export const EXPERIENCE_FLOW_STATUS = Object.freeze({
    NOT_STARTED: 'not_started',
    IN_PROGRESS: 'in_progress',
    COMPLETED: 'completed',
    INTERRUPTED: 'interrupted',
});

const LEGACY_STORAGE_KEY = STORAGE_KEY;
const LOCAL_UPDATED_SUFFIX = '__updated_at';
const REMOTE_TABLE = 'user_data';
const REMOTE_SYNC_DEBOUNCE_MS = 250;
const EXPERIENCE_FLOW_STATUS_SET = new Set(Object.values(EXPERIENCE_FLOW_STATUS));

export const EMPTY_STORE = {
    version: STORAGE_VERSION,
    personalStudies: [],
    notes: [],
    experiments: [],
    interventionRatings: [],
    dailyCheckIns: {},          // { 'YYYY-MM-DD': ['INTERVENTION_ID', ...] }
    nightExposures: [],         // [{ nightId, interventionId, enabled, intensity?, tags?, createdAt }]
    nightOutcomes: [],          // [{ nightId, microArousalCount?, microArousalRatePerHour?, ... }]
    morningStates: [],          // [{ nightId, globalSensation?, neckTightness?, ... }]
    habitTrials: [],            // [{ id, interventionId, startNightId, ... }]
    habitClassifications: [],   // [{ interventionId, status, nightsOn, nightsOff, ... }]
    hiddenInterventions: [],    // IDs of interventions hidden from check-in list
    unlockedAchievements: [],   // Achievement IDs that have been earned
    customCausalDiagram: undefined,
    experienceFlow: createDefaultExperienceFlow(),
};

let currentUserId = null;
let currentStorageKey = STORAGE_KEY;
let currentStore = createEmptyStore();
let isInitialized = false;

let remoteClient = null;
let syncTimer = null;
let queuedSyncKind = null; // 'upsert' | 'delete'
let syncInFlightPromise = null;

/**
 * Create a fresh empty store instance with isolated nested structures.
 */
export function createEmptyStore() {
    return {
        version: STORAGE_VERSION,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings: [],
        dailyCheckIns: {},
        nightExposures: [],
        nightOutcomes: [],
        morningStates: [],
        habitTrials: [],
        habitClassifications: [],
        hiddenInterventions: [],
        unlockedAchievements: [],
        customCausalDiagram: undefined,
        experienceFlow: createDefaultExperienceFlow(),
    };
}

export function createDefaultExperienceFlow() {
    return {
        hasCompletedInitialGuidedFlow: false,
        lastGuidedEntryDate: null,
        lastGuidedCompletedDate: null,
        lastGuidedStatus: EXPERIENCE_FLOW_STATUS.NOT_STARTED,
    };
}

function normalizeGuidedStatus(status) {
    if (typeof status === 'string' && EXPERIENCE_FLOW_STATUS_SET.has(status)) {
        return status;
    }
    return EXPERIENCE_FLOW_STATUS.NOT_STARTED;
}

function normalizeExperienceFlow(experienceFlow) {
    const base = createDefaultExperienceFlow();
    if (!experienceFlow || typeof experienceFlow !== 'object' || Array.isArray(experienceFlow)) {
        return base;
    }

    return {
        hasCompletedInitialGuidedFlow: Boolean(experienceFlow.hasCompletedInitialGuidedFlow),
        lastGuidedEntryDate: typeof experienceFlow.lastGuidedEntryDate === 'string'
            ? experienceFlow.lastGuidedEntryDate
            : null,
        lastGuidedCompletedDate: typeof experienceFlow.lastGuidedCompletedDate === 'string'
            ? experienceFlow.lastGuidedCompletedDate
            : null,
        lastGuidedStatus: normalizeGuidedStatus(experienceFlow.lastGuidedStatus),
    };
}

function cloneStore(store) {
    if (typeof structuredClone === 'function') {
        return structuredClone(store);
    }
    return JSON.parse(JSON.stringify(store));
}

function storageKeyForUser(userId) {
    return userId ? `${STORAGE_KEY}:${userId}` : STORAGE_KEY;
}

function updatedAtKeyForStorage(storageKey) {
    return `${storageKey}${LOCAL_UPDATED_SUFFIX}`;
}

function getLocalUpdatedAt(storageKey) {
    try {
        const raw = localStorage.getItem(updatedAtKeyForStorage(storageKey));
        if (!raw) return 0;
        const parsed = Date.parse(raw);
        return Number.isFinite(parsed) ? parsed : 0;
    } catch (_) {
        return 0;
    }
}

function writeLocalUpdatedAt(storageKey) {
    try {
        localStorage.setItem(updatedAtKeyForStorage(storageKey), now());
    } catch (_) {
        // Ignore write failures; saveData() handles localStorage errors separately.
    }
}

function removeLocalUpdatedAt(storageKey) {
    try {
        localStorage.removeItem(updatedAtKeyForStorage(storageKey));
    } catch (_) {
        // Ignore cleanup failures.
    }
}

function normalizeData(data) {
    const base = createEmptyStore();
    if (!data || typeof data !== 'object') {
        return base;
    }

    const normalized = {
        ...base,
        ...data,
        version: STORAGE_VERSION,
        personalStudies: Array.isArray(data.personalStudies) ? data.personalStudies : [],
        notes: Array.isArray(data.notes) ? data.notes : [],
        experiments: Array.isArray(data.experiments) ? data.experiments : [],
        interventionRatings: Array.isArray(data.interventionRatings) ? data.interventionRatings : [],
        dailyCheckIns: data.dailyCheckIns && typeof data.dailyCheckIns === 'object' && !Array.isArray(data.dailyCheckIns)
            ? data.dailyCheckIns
            : {},
        nightExposures: Array.isArray(data.nightExposures) ? data.nightExposures : [],
        nightOutcomes: Array.isArray(data.nightOutcomes) ? data.nightOutcomes : [],
        morningStates: Array.isArray(data.morningStates) ? data.morningStates : [],
        habitTrials: Array.isArray(data.habitTrials) ? data.habitTrials : [],
        habitClassifications: Array.isArray(data.habitClassifications) ? data.habitClassifications : [],
        hiddenInterventions: Array.isArray(data.hiddenInterventions) ? data.hiddenInterventions : [],
        unlockedAchievements: Array.isArray(data.unlockedAchievements) ? data.unlockedAchievements : [],
        customCausalDiagram: data.customCausalDiagram || undefined,
        experienceFlow: normalizeExperienceFlow(data.experienceFlow),
    };

    return normalized;
}

function hasMeaningfulData(store) {
    const hasFlowActivity = (() => {
        const flow = normalizeExperienceFlow(store?.experienceFlow);
        return flow.hasCompletedInitialGuidedFlow ||
            Boolean(flow.lastGuidedEntryDate) ||
            Boolean(flow.lastGuidedCompletedDate) ||
            flow.lastGuidedStatus !== EXPERIENCE_FLOW_STATUS.NOT_STARTED;
    })();

    return Boolean(
        (store.personalStudies && store.personalStudies.length) ||
        (store.notes && store.notes.length) ||
        (store.experiments && store.experiments.length) ||
        (store.interventionRatings && store.interventionRatings.length) ||
        (store.nightExposures && store.nightExposures.length) ||
        (store.nightOutcomes && store.nightOutcomes.length) ||
        (store.morningStates && store.morningStates.length) ||
        (store.habitTrials && store.habitTrials.length) ||
        (store.habitClassifications && store.habitClassifications.length) ||
        (store.hiddenInterventions && store.hiddenInterventions.length) ||
        (store.unlockedAchievements && store.unlockedAchievements.length) ||
        (store.dailyCheckIns && Object.keys(store.dailyCheckIns).length) ||
        store.customCausalDiagram ||
        hasFlowActivity
    );
}

function readStoreFromLocal(storageKey) {
    try {
        const raw = localStorage.getItem(storageKey);
        if (!raw) {
            return createEmptyStore();
        }

        const parsed = JSON.parse(raw);
        if (parsed.version !== STORAGE_VERSION) {
            return migrateData(parsed);
        }

        return normalizeData(parsed);
    } catch (error) {
        console.error('Failed to load personal data:', error);
        return createEmptyStore();
    }
}

function writeStoreToLocal(storageKey, data) {
    const normalized = normalizeData(data);
    localStorage.setItem(storageKey, JSON.stringify(normalized));
    writeLocalUpdatedAt(storageKey);
}

function removeStoreFromLocal(storageKey) {
    localStorage.removeItem(storageKey);
    removeLocalUpdatedAt(storageKey);
}

function ensureInitialized() {
    if (isInitialized) return;
    currentStore = readStoreFromLocal(currentStorageKey);
    isInitialized = true;
}

function configureStorageIdentity({ userId = null, supabaseClient = null } = {}) {
    currentUserId = userId || null;
    currentStorageKey = storageKeyForUser(currentUserId);
    remoteClient = supabaseClient || null;
    currentStore = readStoreFromLocal(currentStorageKey);
    isInitialized = true;

    // Reset any pending sync state when identity changes.
    if (syncTimer) {
        clearTimeout(syncTimer);
        syncTimer = null;
    }
    queuedSyncKind = null;
}

async function fetchRemoteRow() {
    if (!remoteClient || !currentUserId) {
        return null;
    }

    const { data, error } = await remoteClient
        .from(REMOTE_TABLE)
        .select('data, updated_at')
        .eq('user_id', currentUserId)
        .maybeSingle();

    if (error) {
        console.error('Failed to fetch remote user data:', error);
        return null;
    }

    if (!data || !data.data) {
        return null;
    }

    return {
        store: normalizeData(data.data),
        updatedAt: data.updated_at ? Date.parse(data.updated_at) : 0,
    };
}

function queueRemoteSync(kind, { immediate = false } = {}) {
    if (!remoteClient || !currentUserId) {
        return;
    }

    // Delete takes priority over upsert when both are queued.
    queuedSyncKind = kind === 'delete' || queuedSyncKind === 'delete' ? 'delete' : 'upsert';

    if (syncTimer) {
        clearTimeout(syncTimer);
        syncTimer = null;
    }

    if (immediate) {
        void flushRemoteSync();
        return;
    }

    syncTimer = setTimeout(() => {
        syncTimer = null;
        void flushRemoteSync();
    }, REMOTE_SYNC_DEBOUNCE_MS);
}

async function performUpsert() {
    const payload = {
        user_id: currentUserId,
        data: normalizeData(currentStore),
        updated_at: now(),
    };

    const { error } = await remoteClient
        .from(REMOTE_TABLE)
        .upsert(payload, { onConflict: 'user_id' });

    if (error) {
        console.error('Failed to sync user data to Supabase:', error);
    }
}

async function performDelete() {
    const { error } = await remoteClient
        .from(REMOTE_TABLE)
        .delete()
        .eq('user_id', currentUserId);

    if (error) {
        console.error('Failed to delete user data in Supabase:', error);
    }
}

/**
 * Configure storage for the currently authenticated user and hydrate local state
 * from Supabase. If both local and remote stores exist, the newest updated-at
 * timestamp wins.
 */
export async function initStorageForUser({ supabaseClient = null, userId = null } = {}) {
    configureStorageIdentity({ userId, supabaseClient });

    if (!userId || !supabaseClient) {
        return loadData();
    }

    const userLocal = readStoreFromLocal(currentStorageKey);
    const legacyLocal = readStoreFromLocal(LEGACY_STORAGE_KEY);

    const hasUserLocal = hasMeaningfulData(userLocal);
    const hasLegacyLocal = LEGACY_STORAGE_KEY !== currentStorageKey && hasMeaningfulData(legacyLocal);

    const localCandidate = hasUserLocal ? userLocal : (hasLegacyLocal ? legacyLocal : createEmptyStore());
    const localUpdatedAt = hasUserLocal
        ? getLocalUpdatedAt(currentStorageKey)
        : hasLegacyLocal
            ? getLocalUpdatedAt(LEGACY_STORAGE_KEY)
            : 0;

    const remoteRow = await fetchRemoteRow();

    if (remoteRow && hasMeaningfulData(remoteRow.store)) {
        if (hasMeaningfulData(localCandidate) && localUpdatedAt > remoteRow.updatedAt) {
            currentStore = normalizeData(localCandidate);
            writeStoreToLocal(currentStorageKey, currentStore);
            queueRemoteSync('upsert', { immediate: true });
        } else {
            currentStore = normalizeData(remoteRow.store);
            writeStoreToLocal(currentStorageKey, currentStore);
        }
    } else {
        currentStore = normalizeData(localCandidate);
        writeStoreToLocal(currentStorageKey, currentStore);
        if (hasMeaningfulData(currentStore)) {
            queueRemoteSync('upsert', { immediate: true });
        }
    }

    return loadData();
}

/**
 * Flush any pending remote sync work. Useful before forced reload flows.
 */
export async function flushRemoteSync() {
    if (!remoteClient || !currentUserId) {
        return;
    }

    if (syncTimer) {
        clearTimeout(syncTimer);
        syncTimer = null;
    }

    if (syncInFlightPromise) {
        await syncInFlightPromise;
        if (!queuedSyncKind) return;
    }

    while (queuedSyncKind) {
        const kind = queuedSyncKind;
        queuedSyncKind = null;

        syncInFlightPromise = kind === 'delete' ? performDelete() : performUpsert();
        await syncInFlightPromise;
        syncInFlightPromise = null;
    }
}

// Generate unique ID
export function generateId() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2);
}

// Get current timestamp
export function now() {
    return new Date().toISOString();
}

// Date helper used by daily check-ins
export function dateKey(date) {
    if (typeof date === 'string') return date;
    return date.toISOString().split('T')[0];
}

/**
 * Load personal data from in-memory/local storage.
 * Returns a fresh copy to avoid accidental mutation leaks.
 */
export function loadData() {
    ensureInitialized();
    return cloneStore(currentStore);
}

/**
 * Save personal data to local storage and queue remote sync if configured.
 */
export function saveData(data) {
    ensureInitialized();

    try {
        currentStore = normalizeData(data);
        writeStoreToLocal(currentStorageKey, currentStore);
        queueRemoteSync('upsert');
        return true;
    } catch (error) {
        console.error('Failed to save personal data:', error);
        return false;
    }
}

/**
 * Clear all personal data.
 */
export function clearData() {
    ensureInitialized();
    currentStore = createEmptyStore();

    try {
        removeStoreFromLocal(currentStorageKey);
    } catch (error) {
        console.error('Failed to clear personal data:', error);
    }

    queueRemoteSync('delete');
    return createEmptyStore();
}

/**
 * Migrate data from older versions.
 */
function migrateData(data) {
    // Future: handle version migrations.
    return normalizeData({ ...createEmptyStore(), ...data, version: STORAGE_VERSION });
}
