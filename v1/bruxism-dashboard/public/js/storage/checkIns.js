import { dateKey, loadData, saveData } from './core.js';

export function toggleCheckIn(date, interventionId) {
    const data = loadData();
    if (!data.dailyCheckIns) data.dailyCheckIns = {};
    const key = dateKey(date);
    if (!data.dailyCheckIns[key]) data.dailyCheckIns[key] = [];
    const idx = data.dailyCheckIns[key].indexOf(interventionId);
    if (idx >= 0) {
        data.dailyCheckIns[key].splice(idx, 1);
    } else {
        data.dailyCheckIns[key].push(interventionId);
    }
    saveData(data);
    return data.dailyCheckIns[key];
}

export function getCheckIns(date) {
    const data = loadData();
    if (!data.dailyCheckIns) return [];
    return data.dailyCheckIns[dateKey(date)] || [];
}

export function getCheckInsRange(days = 7) {
    const data = loadData();
    if (!data.dailyCheckIns) return {};
    const result = {};
    const today = new Date();
    for (let i = 0; i < days; i++) {
        const d = new Date(today);
        d.setDate(d.getDate() - i);
        const key = dateKey(d);
        result[key] = data.dailyCheckIns[key] || [];
    }
    return result;
}

export function getStreakCount(interventionId, days = 7) {
    const range = getCheckInsRange(days);
    let count = 0;
    Object.values(range).forEach(ids => {
        if (ids.includes(interventionId)) count++;
    });
    return count;
}
