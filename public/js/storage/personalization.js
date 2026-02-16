import { HABIT_STATUS, SIMPLE_EXPERIMENT_PROTOCOL } from './core.js';
import { loadData, now, saveData } from './core.js';

function numeric(value) {
    return typeof value === 'number' && Number.isFinite(value);
}

function mean(values) {
    if (!Array.isArray(values) || values.length === 0) return undefined;
    const total = values.reduce((sum, value) => sum + value, 0);
    return total / values.length;
}

function objectiveOutcomeValue(outcome) {
    if (!outcome || typeof outcome !== 'object') return undefined;
    if (numeric(outcome.microArousalRatePerHour)) return outcome.microArousalRatePerHour;
    if (numeric(outcome.microArousalCount)) return outcome.microArousalCount;
    return undefined;
}

function morningComposite(state) {
    if (!state || typeof state !== 'object') return undefined;
    const parts = [
        state.globalSensation,
        state.neckTightness,
        state.jawSoreness,
        state.earFullness,
    ].filter(numeric);
    return mean(parts);
}

function protocolConfig(overrides = {}) {
    return {
        ...SIMPLE_EXPERIMENT_PROTOCOL,
        ...overrides,
    };
}

function buildExposureIndex(exposures) {
    const enabledByNight = new Map();
    const interventions = new Set();

    exposures.forEach(exposure => {
        if (!exposure || !exposure.nightId || !exposure.interventionId) return;
        interventions.add(exposure.interventionId);

        if (!enabledByNight.has(exposure.nightId)) {
            enabledByNight.set(exposure.nightId, new Set());
        }

        if (exposure.enabled) {
            enabledByNight.get(exposure.nightId).add(exposure.interventionId);
        }
    });

    return { enabledByNight, interventions };
}

function buildObjectiveMap(outcomes) {
    const map = new Map();
    outcomes.forEach(outcome => {
        if (!outcome || !outcome.nightId) return;
        const value = objectiveOutcomeValue(outcome);
        if (!numeric(value)) return;
        map.set(outcome.nightId, value);
    });
    return map;
}

function buildMorningMap(morningStates) {
    const map = new Map();
    morningStates.forEach(state => {
        if (!state || !state.nightId) return;
        const value = morningComposite(state);
        if (!numeric(value)) return;
        map.set(state.nightId, value);
    });
    return map;
}

function classifyIntervention({
    interventionId,
    objectiveByNight,
    morningByNight,
    enabledByNight,
    settings,
}) {
    const onObjective = [];
    const offObjective = [];
    const onMorning = [];
    const offMorning = [];
    let hasConfoundedNight = false;

    objectiveByNight.forEach((objectiveValue, nightId) => {
        const enabled = enabledByNight.get(nightId) || new Set();
        const morningValue = morningByNight.get(nightId);

        if (enabled.size > 1) {
            hasConfoundedNight = true;
            return;
        }

        if (enabled.size === 1 && enabled.has(interventionId)) {
            onObjective.push(objectiveValue);
            if (numeric(morningValue)) onMorning.push(morningValue);
            return;
        }

        if (enabled.size === 0) {
            offObjective.push(objectiveValue);
            if (numeric(morningValue)) offMorning.push(morningValue);
        }
    });

    const nightsOn = onObjective.length;
    const nightsOff = offObjective.length;
    const onMean = mean(onObjective);
    const offMean = mean(offObjective);
    const onMorningMean = mean(onMorning);
    const offMorningMean = mean(offMorning);

    let microArousalDeltaPct;
    if (numeric(onMean) && numeric(offMean) && Math.abs(offMean) > 1e-9) {
        microArousalDeltaPct = ((onMean - offMean) / offMean) * 100;
    }

    let morningStateDelta;
    if (numeric(onMorningMean) && numeric(offMorningMean)) {
        morningStateDelta = onMorningMean - offMorningMean;
    }

    const enoughData = nightsOn >= settings.minNightsOn && nightsOff >= settings.minNightsOff;
    const canClassify = enoughData && numeric(microArousalDeltaPct);

    let status = HABIT_STATUS.UNKNOWN;
    if (canClassify) {
        const harmfulFromMicro = microArousalDeltaPct >= settings.harmfulThresholdPct;
        const harmfulFromMorning = numeric(morningStateDelta) && morningStateDelta >= settings.morningWorseThreshold;
        if (harmfulFromMicro || harmfulFromMorning) {
            status = HABIT_STATUS.HARMFUL;
        } else if (microArousalDeltaPct <= settings.helpfulThresholdPct) {
            status = HABIT_STATUS.HELPFUL;
        } else {
            status = HABIT_STATUS.NEUTRAL;
        }
    }

    let windowQuality = 'clean_one_variable';
    if (!enoughData) {
        windowQuality = 'insufficient_data';
    } else if (hasConfoundedNight) {
        windowQuality = 'confounded';
    }

    return {
        interventionId,
        status,
        nightsOn,
        nightsOff,
        microArousalDeltaPct: numeric(microArousalDeltaPct) ? Number(microArousalDeltaPct.toFixed(3)) : undefined,
        morningStateDelta: numeric(morningStateDelta) ? Number(morningStateDelta.toFixed(3)) : undefined,
        windowQuality,
        updatedAt: now(),
    };
}

export function computeHabitClassifications(data, overrides = {}) {
    const store = data && typeof data === 'object' ? data : {};
    const exposures = Array.isArray(store.nightExposures) ? store.nightExposures : [];
    const outcomes = Array.isArray(store.nightOutcomes) ? store.nightOutcomes : [];
    const morningStates = Array.isArray(store.morningStates) ? store.morningStates : [];

    const { enabledByNight, interventions } = buildExposureIndex(exposures);
    const objectiveByNight = buildObjectiveMap(outcomes);
    const morningByNight = buildMorningMap(morningStates);
    const settings = protocolConfig(overrides);

    return [...interventions]
        .sort((a, b) => a.localeCompare(b))
        .map(interventionId => classifyIntervention({
            interventionId,
            objectiveByNight,
            morningByNight,
            enabledByNight,
            settings,
        }));
}

export function recomputeHabitClassifications(overrides = {}) {
    const data = loadData();
    data.habitClassifications = computeHabitClassifications(data, overrides);
    saveData(data);
    return data.habitClassifications;
}
