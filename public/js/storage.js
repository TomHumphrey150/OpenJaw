/**
 * Personal Data Storage Service
 * Split into focused domain modules; this file preserves the existing API.
 */

export { loadData, saveData, clearData, initStorageForUser, flushRemoteSync } from './storage/core.js';

export {
    addStudy,
    updateStudy,
    deleteStudy,
    getPersonalStudies,
} from './storage/studies.js';

export {
    addNote,
    updateNote,
    deleteNote,
    getNotesFor,
    getAllNotes,
} from './storage/notes.js';

export {
    startExperiment,
    addObservation,
    completeExperiment,
    abandonExperiment,
    getActiveExperiments,
    getCompletedExperiments,
    getAllExperiments,
    getExperimentForIntervention,
} from './storage/experiments.js';

export {
    setRating,
    getRating,
    getAllRatings,
} from './storage/ratings.js';

export {
    toggleCheckIn,
    getCheckIns,
    getCheckInsRange,
    getStreakCount,
} from './storage/checkIns.js';

export {
    upsertNightExposure,
    deleteNightExposure,
    getNightExposure,
    getNightExposures,
} from './storage/exposures.js';

export {
    upsertNightOutcome,
    getNightOutcome,
    getNightOutcomes,
    upsertMorningState,
    getMorningState,
    getMorningStates,
} from './storage/outcomes.js';

export {
    startHabitTrial,
    completeHabitTrial,
    abandonHabitTrial,
    getHabitTrials,
    upsertHabitClassification,
    getHabitClassification,
    getHabitClassifications,
} from './storage/protocol.js';

export {
    toggleHiddenIntervention,
    getHiddenInterventions,
} from './storage/hiddenInterventions.js';

export {
    saveDiagram,
    getDiagram,
    clearDiagram,
} from './storage/diagram.js';

export {
    unlockAchievement,
    getUnlockedAchievements,
} from './storage/achievements.js';

export {
    exportData,
    importData,
    downloadExport,
} from './storage/io.js';

import { loadData, saveData, clearData, initStorageForUser, flushRemoteSync } from './storage/core.js';
import { addStudy, updateStudy, deleteStudy, getPersonalStudies } from './storage/studies.js';
import { addNote, updateNote, deleteNote, getNotesFor, getAllNotes } from './storage/notes.js';
import {
    startExperiment,
    addObservation,
    completeExperiment,
    abandonExperiment,
    getActiveExperiments,
    getCompletedExperiments,
    getAllExperiments,
    getExperimentForIntervention,
} from './storage/experiments.js';
import { setRating, getRating, getAllRatings } from './storage/ratings.js';
import { toggleCheckIn, getCheckIns, getCheckInsRange, getStreakCount } from './storage/checkIns.js';
import { upsertNightExposure, deleteNightExposure, getNightExposure, getNightExposures } from './storage/exposures.js';
import {
    upsertNightOutcome,
    getNightOutcome,
    getNightOutcomes,
    upsertMorningState,
    getMorningState,
    getMorningStates,
} from './storage/outcomes.js';
import {
    startHabitTrial,
    completeHabitTrial,
    abandonHabitTrial,
    getHabitTrials,
    upsertHabitClassification,
    getHabitClassification,
    getHabitClassifications,
} from './storage/protocol.js';
import { toggleHiddenIntervention, getHiddenInterventions } from './storage/hiddenInterventions.js';
import { saveDiagram, getDiagram, clearDiagram } from './storage/diagram.js';
import { unlockAchievement, getUnlockedAchievements } from './storage/achievements.js';
import { exportData, importData, downloadExport } from './storage/io.js';

// Default export for convenience
export default {
    loadData,
    saveData,
    clearData,
    initStorageForUser,
    flushRemoteSync,
    addStudy,
    updateStudy,
    deleteStudy,
    getPersonalStudies,
    addNote,
    updateNote,
    deleteNote,
    getNotesFor,
    getAllNotes,
    startExperiment,
    addObservation,
    completeExperiment,
    abandonExperiment,
    getActiveExperiments,
    getCompletedExperiments,
    getAllExperiments,
    getExperimentForIntervention,
    setRating,
    getRating,
    getAllRatings,
    toggleCheckIn,
    getCheckIns,
    getCheckInsRange,
    getStreakCount,
    upsertNightExposure,
    deleteNightExposure,
    getNightExposure,
    getNightExposures,
    upsertNightOutcome,
    getNightOutcome,
    getNightOutcomes,
    upsertMorningState,
    getMorningState,
    getMorningStates,
    startHabitTrial,
    completeHabitTrial,
    abandonHabitTrial,
    getHabitTrials,
    upsertHabitClassification,
    getHabitClassification,
    getHabitClassifications,
    toggleHiddenIntervention,
    getHiddenInterventions,
    unlockAchievement,
    getUnlockedAchievements,
    saveDiagram,
    getDiagram,
    clearDiagram,
    exportData,
    importData,
    downloadExport,
};
