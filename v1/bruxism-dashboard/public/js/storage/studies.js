import { generateId, loadData, now, saveData } from './core.js';

export function addStudy(study) {
    const data = loadData();
    const newStudy = {
        ...study,
        id: study.id || generateId(),
        isPersonal: true,
        addedAt: now(),
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
