import { dateKey, loadData, now, saveData } from './core.js';

function normalizeNightId(nightId) {
    if (!nightId) {
        return dateKey(new Date());
    }
    return dateKey(nightId);
}

function upsertByNight(records, nextRecord) {
    const index = records.findIndex(record => record.nightId === nextRecord.nightId);
    if (index >= 0) {
        const merged = { ...records[index] };
        Object.entries(nextRecord).forEach(([key, value]) => {
            if (value !== undefined) {
                merged[key] = value;
            }
        });
        records[index] = {
            ...merged,
            createdAt: records[index].createdAt || nextRecord.createdAt || now(),
        };
        return records[index];
    }

    records.push(nextRecord);
    return nextRecord;
}

export function upsertNightOutcome({
    nightId,
    microArousalCount = undefined,
    microArousalRatePerHour = undefined,
    confidence = undefined,
    totalSleepMinutes = undefined,
    source = undefined,
} = {}) {
    const data = loadData();
    if (!Array.isArray(data.nightOutcomes)) {
        data.nightOutcomes = [];
    }

    const record = {
        nightId: normalizeNightId(nightId),
        microArousalCount: typeof microArousalCount === 'number' ? microArousalCount : undefined,
        microArousalRatePerHour: typeof microArousalRatePerHour === 'number' ? microArousalRatePerHour : undefined,
        confidence: typeof confidence === 'number' ? confidence : undefined,
        totalSleepMinutes: typeof totalSleepMinutes === 'number' ? totalSleepMinutes : undefined,
        source: typeof source === 'string' ? source : undefined,
        createdAt: now(),
    };

    const saved = upsertByNight(data.nightOutcomes, record);
    saveData(data);
    return saved;
}

export function getNightOutcome(nightId) {
    const normalizedNightId = normalizeNightId(nightId);
    const data = loadData();
    const outcomes = Array.isArray(data.nightOutcomes) ? data.nightOutcomes : [];
    return outcomes.find(outcome => outcome.nightId === normalizedNightId);
}

export function getNightOutcomes() {
    const data = loadData();
    return Array.isArray(data.nightOutcomes) ? data.nightOutcomes : [];
}

export function upsertMorningState({
    nightId,
    globalSensation = undefined,
    neckTightness = undefined,
    jawSoreness = undefined,
    earFullness = undefined,
    healthAnxiety = undefined,
} = {}) {
    const data = loadData();
    if (!Array.isArray(data.morningStates)) {
        data.morningStates = [];
    }

    const record = {
        nightId: normalizeNightId(nightId),
        globalSensation: typeof globalSensation === 'number' ? globalSensation : undefined,
        neckTightness: typeof neckTightness === 'number' ? neckTightness : undefined,
        jawSoreness: typeof jawSoreness === 'number' ? jawSoreness : undefined,
        earFullness: typeof earFullness === 'number' ? earFullness : undefined,
        healthAnxiety: typeof healthAnxiety === 'number' ? healthAnxiety : undefined,
        createdAt: now(),
    };

    const saved = upsertByNight(data.morningStates, record);
    saveData(data);
    return saved;
}

export function getMorningState(nightId) {
    const normalizedNightId = normalizeNightId(nightId);
    const data = loadData();
    const states = Array.isArray(data.morningStates) ? data.morningStates : [];
    return states.find(state => state.nightId === normalizedNightId);
}

export function getMorningStates() {
    const data = loadData();
    return Array.isArray(data.morningStates) ? data.morningStates : [];
}
