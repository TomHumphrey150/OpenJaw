import { loadData, now, saveData } from './core.js';

export function setRating(interventionId, effectiveness, notes = '') {
    const data = loadData();
    const existing = data.interventionRatings.findIndex(r => r.interventionId === interventionId);

    const rating = {
        interventionId,
        effectiveness,
        notes,
        lastUpdated: now(),
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
