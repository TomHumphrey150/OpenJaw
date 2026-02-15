import { loadData, saveData } from './core.js';

export function unlockAchievement(id) {
    const data = loadData();
    if (!data.unlockedAchievements) data.unlockedAchievements = [];
    if (!data.unlockedAchievements.includes(id)) {
        data.unlockedAchievements.push(id);
        saveData(data);
        return true; // newly unlocked
    }
    return false; // already had it
}

export function getUnlockedAchievements() {
    const data = loadData();
    return data.unlockedAchievements || [];
}
