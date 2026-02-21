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
        dataset: {},
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
        setAttribute(name, value) {
            this[name] = value;
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
    const listeners = new Map();
    for (const id of elementIds) {
        elements.set(id, createMockElement({ id }));
    }

    return {
        visibilityState: 'visible',
        getElementById(id) {
            return elements.get(id) || null;
        },
        addEventListener(type, handler) {
            const existing = listeners.get(type) || [];
            existing.push(handler);
            listeners.set(type, existing);
        },
        removeEventListener(type, handler) {
            const existing = listeners.get(type) || [];
            listeners.set(type, existing.filter((fn) => fn !== handler));
        },
        async trigger(type, eventOverrides = {}) {
            const handlers = listeners.get(type) || [];
            const event = { type, target: this, ...eventOverrides };
            for (const handler of handlers) {
                await handler(event);
            }
        },
        elements,
    };
}
