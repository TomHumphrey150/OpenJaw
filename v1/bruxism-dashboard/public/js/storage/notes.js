import { generateId, loadData, now, saveData } from './core.js';

export function addNote(targetType, targetId, content) {
    const data = loadData();
    const note = {
        id: generateId(),
        targetType,
        targetId,
        content,
        createdAt: now(),
        updatedAt: now(),
    };
    data.notes.push(note);
    saveData(data);
    return note;
}

export function updateNote(id, content) {
    const data = loadData();
    const index = data.notes.findIndex(n => n.id === id);
    if (index >= 0) {
        data.notes[index].content = content;
        data.notes[index].updatedAt = now();
        saveData(data);
        return data.notes[index];
    }
    return null;
}

export function deleteNote(id) {
    const data = loadData();
    data.notes = data.notes.filter(n => n.id !== id);
    saveData(data);
}

export function getNotesFor(targetType, targetId) {
    const data = loadData();
    return data.notes.filter(n => n.targetType === targetType && n.targetId === targetId);
}

export function getAllNotes() {
    return loadData().notes;
}
