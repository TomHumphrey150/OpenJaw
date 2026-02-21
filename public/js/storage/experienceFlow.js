import {
    createDefaultExperienceFlow,
    EXPERIENCE_FLOW_STATUS,
    loadData,
    saveData,
} from './core.js';

export { EXPERIENCE_FLOW_STATUS };

function normalizeDateKey(dateOrDateKey) {
    if (typeof dateOrDateKey === 'string' && dateOrDateKey) {
        return dateOrDateKey;
    }

    const date = dateOrDateKey instanceof Date ? dateOrDateKey : new Date();
    const year = String(date.getFullYear());
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function saveExperienceFlow(experienceFlow) {
    const nextStore = loadData();
    nextStore.experienceFlow = {
        ...createDefaultExperienceFlow(),
        ...experienceFlow,
    };
    saveData(nextStore);
    return nextStore.experienceFlow;
}

export function getExperienceFlow() {
    const loaded = loadData();
    return {
        ...createDefaultExperienceFlow(),
        ...(loaded.experienceFlow || {}),
    };
}

export function shouldEnterGuidedFlow(dateOrDateKey = new Date()) {
    const dateKey = normalizeDateKey(dateOrDateKey);
    const flow = getExperienceFlow();
    const firstEverOpen = !flow.hasCompletedInitialGuidedFlow && !flow.lastGuidedEntryDate;
    if (firstEverOpen) {
        return true;
    }
    return flow.lastGuidedEntryDate !== dateKey;
}

export function markGuidedEntry(dateOrDateKey = new Date()) {
    const dateKey = normalizeDateKey(dateOrDateKey);
    const flow = getExperienceFlow();
    return saveExperienceFlow({
        ...flow,
        lastGuidedEntryDate: dateKey,
        lastGuidedStatus: EXPERIENCE_FLOW_STATUS.IN_PROGRESS,
    });
}

export function markGuidedCompleted(dateOrDateKey = new Date()) {
    const dateKey = normalizeDateKey(dateOrDateKey);
    const flow = getExperienceFlow();
    return saveExperienceFlow({
        ...flow,
        hasCompletedInitialGuidedFlow: true,
        lastGuidedEntryDate: dateKey,
        lastGuidedCompletedDate: dateKey,
        lastGuidedStatus: EXPERIENCE_FLOW_STATUS.COMPLETED,
    });
}

export function markGuidedInterrupted(dateOrDateKey = new Date()) {
    const dateKey = normalizeDateKey(dateOrDateKey);
    const flow = getExperienceFlow();
    if (flow.lastGuidedStatus !== EXPERIENCE_FLOW_STATUS.IN_PROGRESS) {
        return flow;
    }

    return saveExperienceFlow({
        ...flow,
        lastGuidedEntryDate: flow.lastGuidedEntryDate || dateKey,
        lastGuidedStatus: EXPERIENCE_FLOW_STATUS.INTERRUPTED,
    });
}
