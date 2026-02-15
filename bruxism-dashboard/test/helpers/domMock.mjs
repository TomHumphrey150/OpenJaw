export function createMockElement({ id = '' } = {}) {
    const listeners = new Map();
    const classes = new Set();

    return {
        id,
        textContent: '',
        value: '',
        disabled: false,
        files: [],
        style: {},
        classList: {
            add(...classNames) {
                classNames.forEach((name) => classes.add(name));
            },
            remove(...classNames) {
                classNames.forEach((name) => classes.delete(name));
            },
            contains(className) {
                return classes.has(className);
            },
        },
        addEventListener(type, handler) {
            const existing = listeners.get(type) || [];
            existing.push(handler);
            listeners.set(type, existing);
        },
        async trigger(type, eventOverrides = {}) {
            const handlers = listeners.get(type) || [];
            const event = { type, target: this, ...eventOverrides };
            for (const handler of handlers) {
                await handler(event);
            }
        },
        click() {
            return this.trigger('click');
        },
    };
}

export function createMockDocument(elementIds = []) {
    const elements = new Map();
    for (const id of elementIds) {
        elements.set(id, createMockElement({ id }));
    }

    return {
        getElementById(id) {
            return elements.get(id) || null;
        },
        elements,
    };
}
