import { generateId, loadData, now, saveData } from './core.js';
import { setRating } from './ratings.js';

export function startExperiment(interventionId, interventionName) {
    const data = loadData();
    const experiment = {
        id: generateId(),
        interventionId,
        interventionName,
        startDate: now(),
        status: 'active',
        observations: [],
        effectiveness: 'untested',
    };
    data.experiments.push(experiment);
    saveData(data);
    return experiment;
}

export function addObservation(experimentId, note, rating = null) {
    const data = loadData();
    const experiment = data.experiments.find(e => e.id === experimentId);
    if (experiment) {
        const observation = {
            id: generateId(),
            date: now(),
            note,
            rating,
        };
        experiment.observations.push(observation);
        saveData(data);
        return observation;
    }
    return null;
}

export function completeExperiment(experimentId, effectiveness, summary = '') {
    const data = loadData();
    const experiment = data.experiments.find(e => e.id === experimentId);
    if (experiment) {
        experiment.status = 'completed';
        experiment.endDate = now();
        experiment.effectiveness = effectiveness;
        experiment.summary = summary;
        saveData(data);

        // Also update the intervention rating
        setRating(experiment.interventionId, effectiveness, summary);

        return experiment;
    }
    return null;
}

export function abandonExperiment(experimentId) {
    const data = loadData();
    const experiment = data.experiments.find(e => e.id === experimentId);
    if (experiment) {
        experiment.status = 'abandoned';
        experiment.endDate = now();
        saveData(data);
        return experiment;
    }
    return null;
}

export function getActiveExperiments() {
    return loadData().experiments.filter(e => e.status === 'active');
}

export function getCompletedExperiments() {
    return loadData().experiments.filter(e => e.status === 'completed');
}

export function getAllExperiments() {
    return loadData().experiments;
}

export function getExperimentForIntervention(interventionId) {
    const data = loadData();
    return data.experiments.find(e => e.interventionId === interventionId && e.status === 'active');
}
