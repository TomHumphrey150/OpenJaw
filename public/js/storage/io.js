import { loadData, now, saveData, STORAGE_VERSION } from './core.js';

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
            dailyCheckIns: (data.dailyCheckIns && typeof data.dailyCheckIns === 'object') ? data.dailyCheckIns : {},
            nightExposures: Array.isArray(data.nightExposures) ? data.nightExposures : [],
            nightOutcomes: Array.isArray(data.nightOutcomes) ? data.nightOutcomes : [],
            morningStates: Array.isArray(data.morningStates) ? data.morningStates : [],
            habitTrials: Array.isArray(data.habitTrials) ? data.habitTrials : [],
            habitClassifications: Array.isArray(data.habitClassifications) ? data.habitClassifications : [],
            hiddenInterventions: Array.isArray(data.hiddenInterventions) ? data.hiddenInterventions : [],
            unlockedAchievements: Array.isArray(data.unlockedAchievements) ? data.unlockedAchievements : [],
            customCausalDiagram: data.customCausalDiagram || undefined,
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
