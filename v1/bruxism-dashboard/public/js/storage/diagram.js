import { loadData, now, saveData } from './core.js';

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
