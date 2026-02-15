/**
 * Shared storage core utilities.
 */

export const STORAGE_KEY = 'bruxism_personal_data';
export const STORAGE_VERSION = 1;

export const EMPTY_STORE = {
    version: STORAGE_VERSION,
    personalStudies: [],
    notes: [],
    experiments: [],
    interventionRatings: [],
    dailyCheckIns: {},          // { 'YYYY-MM-DD': ['INTERVENTION_ID', ...] }
    hiddenInterventions: [],    // IDs of interventions hidden from check-in list
    unlockedAchievements: [],   // Achievement IDs that have been earned
    customCausalDiagram: undefined,
};

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
        hiddenInterventions: [],
        unlockedAchievements: [],
        customCausalDiagram: undefined,
    };
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
 * Load personal data from localStorage
 */
export function loadData() {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) return createEmptyStore();

        const data = JSON.parse(raw);

        // Version migration if needed
        if (data.version !== STORAGE_VERSION) {
            return migrateData(data);
        }

        return data;
    } catch (error) {
        console.error('Failed to load personal data:', error);
        return createEmptyStore();
    }
}

/**
 * Save personal data to localStorage
 */
export function saveData(data) {
    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
        return true;
    } catch (error) {
        console.error('Failed to save personal data:', error);
        return false;
    }
}

/**
 * Clear all personal data
 */
export function clearData() {
    localStorage.removeItem(STORAGE_KEY);
    return createEmptyStore();
}

/**
 * Migrate data from older versions
 */
function migrateData(data) {
    // Future: handle version migrations
    return { ...createEmptyStore(), ...data, version: STORAGE_VERSION };
}
