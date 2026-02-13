import { loadData, saveData } from './core.js';

export function toggleHiddenIntervention(interventionId) {
    const data = loadData();
    if (!data.hiddenInterventions) data.hiddenInterventions = [];
    const idx = data.hiddenInterventions.indexOf(interventionId);
    if (idx >= 0) {
        data.hiddenInterventions.splice(idx, 1);
    } else {
        data.hiddenInterventions.push(interventionId);
    }
    saveData(data);
    return data.hiddenInterventions;
}

export function getHiddenInterventions() {
    const data = loadData();
    return data.hiddenInterventions || [];
}
