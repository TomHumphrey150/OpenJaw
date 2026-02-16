import { dateKey, generateId, loadData, now, saveData } from './core.js';
import { HABIT_STATUS } from './core.js';

function normalizeNightId(nightId) {
    if (!nightId) {
        return dateKey(new Date());
    }
    return dateKey(nightId);
}

function normalizeStatus(status) {
    if (!status || typeof status !== 'string') {
        return HABIT_STATUS.UNKNOWN;
    }

    const normalized = status.toLowerCase();
    if (Object.values(HABIT_STATUS).includes(normalized)) {
        return normalized;
    }

    return HABIT_STATUS.UNKNOWN;
}

export function startHabitTrial(interventionId, startNightId = null) {
    if (!interventionId) return null;
    const data = loadData();
    if (!Array.isArray(data.habitTrials)) {
        data.habitTrials = [];
    }

    const trial = {
        id: generateId(),
        interventionId,
        startNightId: normalizeNightId(startNightId),
        status: 'active',
    };

    data.habitTrials.push(trial);
    saveData(data);
    return trial;
}

export function completeHabitTrial(trialId, endNightId = null) {
    if (!trialId) return null;
    const data = loadData();
    const trials = Array.isArray(data.habitTrials) ? data.habitTrials : [];
    const trial = trials.find(item => item.id === trialId);
    if (!trial) return null;

    trial.status = 'completed';
    trial.endNightId = normalizeNightId(endNightId);
    saveData(data);
    return trial;
}

export function abandonHabitTrial(trialId, endNightId = null) {
    if (!trialId) return null;
    const data = loadData();
    const trials = Array.isArray(data.habitTrials) ? data.habitTrials : [];
    const trial = trials.find(item => item.id === trialId);
    if (!trial) return null;

    trial.status = 'abandoned';
    trial.endNightId = normalizeNightId(endNightId);
    saveData(data);
    return trial;
}

export function getHabitTrials() {
    const data = loadData();
    return Array.isArray(data.habitTrials) ? data.habitTrials : [];
}

export function upsertHabitClassification({
    interventionId,
    status = HABIT_STATUS.UNKNOWN,
    nightsOn = 0,
    nightsOff = 0,
    microArousalDeltaPct = undefined,
    morningStateDelta = undefined,
    windowQuality = undefined,
} = {}) {
    if (!interventionId) return null;
    const data = loadData();
    if (!Array.isArray(data.habitClassifications)) {
        data.habitClassifications = [];
    }

    const next = {
        interventionId,
        status: normalizeStatus(status),
        nightsOn: Number.isFinite(nightsOn) ? nightsOn : 0,
        nightsOff: Number.isFinite(nightsOff) ? nightsOff : 0,
        microArousalDeltaPct: Number.isFinite(microArousalDeltaPct) ? microArousalDeltaPct : undefined,
        morningStateDelta: Number.isFinite(morningStateDelta) ? morningStateDelta : undefined,
        windowQuality: typeof windowQuality === 'string' ? windowQuality : undefined,
        updatedAt: now(),
    };

    const existingIndex = data.habitClassifications.findIndex(
        record => record.interventionId === interventionId
    );

    if (existingIndex >= 0) {
        data.habitClassifications[existingIndex] = next;
    } else {
        data.habitClassifications.push(next);
    }

    saveData(data);
    return next;
}

export function getHabitClassification(interventionId) {
    if (!interventionId) return undefined;
    const data = loadData();
    const classifications = Array.isArray(data.habitClassifications) ? data.habitClassifications : [];
    return classifications.find(record => record.interventionId === interventionId);
}

export function getHabitClassifications() {
    const data = loadData();
    return Array.isArray(data.habitClassifications) ? data.habitClassifications : [];
}
