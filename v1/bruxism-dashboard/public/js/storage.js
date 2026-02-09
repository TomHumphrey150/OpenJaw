/**
 * Personal Data Storage Service
 * Stores all user data in localStorage with export/import support
 */

const STORAGE_KEY = 'bruxism_personal_data';
const STORAGE_VERSION = 1;

// Generate unique ID
function generateId() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2);
}

// Get current timestamp
function now() {
    return new Date().toISOString();
}

// Empty store template
const EMPTY_STORE = {
    version: STORAGE_VERSION,
    personalStudies: [],
    notes: [],
    experiments: [],
    interventionRatings: [],
    customCausalDiagram: undefined
};

/**
 * Load personal data from localStorage
 */
export function loadData() {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) return { ...EMPTY_STORE };

        const data = JSON.parse(raw);

        // Version migration if needed
        if (data.version !== STORAGE_VERSION) {
            return migrateData(data);
        }

        return data;
    } catch (error) {
        console.error('Failed to load personal data:', error);
        return { ...EMPTY_STORE };
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
    return { ...EMPTY_STORE };
}

/**
 * Migrate data from older versions
 */
function migrateData(data) {
    // Future: handle version migrations
    return { ...EMPTY_STORE, ...data, version: STORAGE_VERSION };
}

// ===========================================
// Personal Studies
// ===========================================

export function addStudy(study) {
    const data = loadData();
    const newStudy = {
        ...study,
        id: study.id || generateId(),
        isPersonal: true,
        addedAt: now()
    };
    data.personalStudies.push(newStudy);
    saveData(data);
    return newStudy;
}

export function updateStudy(id, updates) {
    const data = loadData();
    const index = data.personalStudies.findIndex(s => s.id === id);
    if (index >= 0) {
        data.personalStudies[index] = { ...data.personalStudies[index], ...updates };
        saveData(data);
        return data.personalStudies[index];
    }
    return null;
}

export function deleteStudy(id) {
    const data = loadData();
    data.personalStudies = data.personalStudies.filter(s => s.id !== id);
    saveData(data);
}

export function getPersonalStudies() {
    return loadData().personalStudies;
}

// ===========================================
// Notes
// ===========================================

export function addNote(targetType, targetId, content) {
    const data = loadData();
    const note = {
        id: generateId(),
        targetType,
        targetId,
        content,
        createdAt: now(),
        updatedAt: now()
    };
    data.notes.push(note);
    saveData(data);
    return note;
}

export function updateNote(id, content) {
    const data = loadData();
    const index = data.notes.findIndex(n => n.id === id);
    if (index >= 0) {
        data.notes[index].content = content;
        data.notes[index].updatedAt = now();
        saveData(data);
        return data.notes[index];
    }
    return null;
}

export function deleteNote(id) {
    const data = loadData();
    data.notes = data.notes.filter(n => n.id !== id);
    saveData(data);
}

export function getNotesFor(targetType, targetId) {
    const data = loadData();
    return data.notes.filter(n => n.targetType === targetType && n.targetId === targetId);
}

export function getAllNotes() {
    return loadData().notes;
}

// ===========================================
// Experiments
// ===========================================

export function startExperiment(interventionId, interventionName) {
    const data = loadData();
    const experiment = {
        id: generateId(),
        interventionId,
        interventionName,
        startDate: now(),
        status: 'active',
        observations: [],
        effectiveness: 'untested'
    };
    data.experiments.push(experiment);
    saveData(data);
    return experiment;
}

export function addObservation(experimentId, note, rating = null) {
    const data = loadData();
    const experiment = data.experiments.find(e => e.id === experimentId);
    if (experiment) {
        const observation = {
            id: generateId(),
            date: now(),
            note,
            rating
        };
        experiment.observations.push(observation);
        saveData(data);
        return observation;
    }
    return null;
}

export function completeExperiment(experimentId, effectiveness, summary = '') {
    const data = loadData();
    const experiment = data.experiments.find(e => e.id === experimentId);
    if (experiment) {
        experiment.status = 'completed';
        experiment.endDate = now();
        experiment.effectiveness = effectiveness;
        experiment.summary = summary;
        saveData(data);

        // Also update the intervention rating
        setRating(experiment.interventionId, effectiveness, summary);

        return experiment;
    }
    return null;
}

export function abandonExperiment(experimentId) {
    const data = loadData();
    const experiment = data.experiments.find(e => e.id === experimentId);
    if (experiment) {
        experiment.status = 'abandoned';
        experiment.endDate = now();
        saveData(data);
        return experiment;
    }
    return null;
}

export function getActiveExperiments() {
    return loadData().experiments.filter(e => e.status === 'active');
}

export function getCompletedExperiments() {
    return loadData().experiments.filter(e => e.status === 'completed');
}

export function getAllExperiments() {
    return loadData().experiments;
}

export function getExperimentForIntervention(interventionId) {
    const data = loadData();
    return data.experiments.find(e => e.interventionId === interventionId && e.status === 'active');
}

// ===========================================
// Intervention Ratings
// ===========================================

export function setRating(interventionId, effectiveness, notes = '') {
    const data = loadData();
    const existing = data.interventionRatings.findIndex(r => r.interventionId === interventionId);

    const rating = {
        interventionId,
        effectiveness,
        notes,
        lastUpdated: now()
    };

    if (existing >= 0) {
        data.interventionRatings[existing] = rating;
    } else {
        data.interventionRatings.push(rating);
    }

    saveData(data);
    return rating;
}

export function getRating(interventionId) {
    const data = loadData();
    return data.interventionRatings.find(r => r.interventionId === interventionId);
}

export function getAllRatings() {
    return loadData().interventionRatings;
}

// ===========================================
// Causal Diagram
// ===========================================

export function saveDiagram(diagram) {
    const data = loadData();
    data.customCausalDiagram = {
        ...diagram,
        lastModified: now()
    };
    saveData(data);
    return data.customCausalDiagram;
}

export function getDiagram() {
    return loadData().customCausalDiagram;
}

export function clearDiagram() {
    const data = loadData();
    data.customCausalDiagram = undefined;
    saveData(data);
}

// ===========================================
// Export / Import
// ===========================================

export function exportData() {
    const data = loadData();
    data.lastExport = now();
    saveData(data);

    return JSON.stringify(data, null, 2);
}

export function importData(jsonString) {
    try {
        const data = JSON.parse(jsonString);

        // Validate structure
        if (typeof data !== 'object' || data === null) {
            return { success: false, errors: ['Invalid JSON structure'] };
        }

        // Ensure required arrays exist
        const validated = {
            version: STORAGE_VERSION,
            personalStudies: Array.isArray(data.personalStudies) ? data.personalStudies : [],
            notes: Array.isArray(data.notes) ? data.notes : [],
            experiments: Array.isArray(data.experiments) ? data.experiments : [],
            interventionRatings: Array.isArray(data.interventionRatings) ? data.interventionRatings : [],
            customCausalDiagram: data.customCausalDiagram || undefined
        };

        saveData(validated);
        return { success: true };
    } catch (error) {
        return { success: false, errors: [error.message] };
    }
}

export function downloadExport() {
    const json = exportData();
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `bruxism-personal-data-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

// Default export for convenience
export default {
    loadData,
    saveData,
    clearData,
    addStudy,
    updateStudy,
    deleteStudy,
    getPersonalStudies,
    addNote,
    updateNote,
    deleteNote,
    getNotesFor,
    getAllNotes,
    startExperiment,
    addObservation,
    completeExperiment,
    abandonExperiment,
    getActiveExperiments,
    getCompletedExperiments,
    getAllExperiments,
    getExperimentForIntervention,
    setRating,
    getRating,
    getAllRatings,
    saveDiagram,
    getDiagram,
    clearDiagram,
    exportData,
    importData,
    downloadExport
};
