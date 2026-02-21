import { loadData, now, saveData } from './core.js';
import { DEFAULT_GRAPH_DATA } from '../causalEditor/defaultGraphData.js';

export function saveDiagram(diagram) {
    const data = loadData();
    data.customCausalDiagram = {
        ...diagram,
        lastModified: now(),
    };
    saveData(data);
    return data.customCausalDiagram;
}

export function getDiagram() {
    return loadData().customCausalDiagram;
}

export function clearDiagram() {
    const data = loadData();
    data.customCausalDiagram = undefined;
    saveData(data);
}

export function hasValidCustomDiagram(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
        return false;
    }

    const wrapped = value.graphData;
    if (wrapped && typeof wrapped === 'object' && !Array.isArray(wrapped)) {
        return Array.isArray(wrapped.nodes) && Array.isArray(wrapped.edges);
    }

    return Array.isArray(value.nodes) && Array.isArray(value.edges);
}

export function canonicalGraphPayload() {
    const graphData = typeof structuredClone === 'function'
        ? structuredClone(DEFAULT_GRAPH_DATA)
        : JSON.parse(JSON.stringify(DEFAULT_GRAPH_DATA));

    return {
        graphData,
        lastModified: now(),
    };
}
