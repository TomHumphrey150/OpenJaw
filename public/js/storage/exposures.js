import { dateKey, loadData, now, saveData } from './core.js';

function normalizeNightId(nightId) {
    if (!nightId) {
        return dateKey(new Date());
    }
    return dateKey(nightId);
}

function normalizeTags(tags) {
    if (!Array.isArray(tags)) return [];
    return tags.filter(tag => typeof tag === 'string' && tag.trim().length > 0);
}

export function upsertNightExposure({
    nightId,
    interventionId,
    enabled = true,
    intensity = undefined,
    tags = [],
} = {}) {
    if (!interventionId) {
        return null;
    }

    const data = loadData();
    if (!Array.isArray(data.nightExposures)) {
        data.nightExposures = [];
    }

    const normalizedNightId = normalizeNightId(nightId);
    const existingIndex = data.nightExposures.findIndex(exposure =>
        exposure.nightId === normalizedNightId && exposure.interventionId === interventionId
    );

    const base = existingIndex >= 0 ? data.nightExposures[existingIndex] : { createdAt: now() };
    const record = {
        ...base,
        nightId: normalizedNightId,
        interventionId,
        enabled: Boolean(enabled),
        intensity: typeof intensity === 'number' ? intensity : undefined,
        tags: normalizeTags(tags),
        createdAt: base.createdAt || now(),
    };

    if (existingIndex >= 0) {
        data.nightExposures[existingIndex] = record;
    } else {
        data.nightExposures.push(record);
    }

    saveData(data);
    return record;
}

export function deleteNightExposure(nightId, interventionId) {
    if (!interventionId) return false;
    const data = loadData();
    if (!Array.isArray(data.nightExposures)) return false;

    const normalizedNightId = normalizeNightId(nightId);
    const before = data.nightExposures.length;
    data.nightExposures = data.nightExposures.filter(exposure =>
        !(exposure.nightId === normalizedNightId && exposure.interventionId === interventionId)
    );

    if (data.nightExposures.length === before) {
        return false;
    }

    saveData(data);
    return true;
}

export function getNightExposure(nightId, interventionId) {
    if (!interventionId) return undefined;
    const normalizedNightId = normalizeNightId(nightId);
    const data = loadData();
    const exposures = Array.isArray(data.nightExposures) ? data.nightExposures : [];
    return exposures.find(exposure =>
        exposure.nightId === normalizedNightId && exposure.interventionId === interventionId
    );
}

export function getNightExposures(nightId = null) {
    const data = loadData();
    const exposures = Array.isArray(data.nightExposures) ? data.nightExposures : [];
    if (!nightId) return exposures;

    const normalizedNightId = normalizeNightId(nightId);
    return exposures.filter(exposure => exposure.nightId === normalizedNightId);
}
