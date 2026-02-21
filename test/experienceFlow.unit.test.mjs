import assert from 'node:assert/strict';
import { test } from 'node:test';

import { initExperienceFlow } from '../public/js/experienceFlow.js';
import { createMockDocument } from './helpers/domMock.mjs';

function createWindowMock() {
    const listeners = new Map();
    return {
        CustomEvent: class {
            constructor(type, init = {}) {
                this.type = type;
                this.detail = init.detail;
            }
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
        dispatchEvent(event) {
            const handlers = listeners.get(event.type) || [];
            handlers.forEach((handler) => handler(event));
            return true;
        },
        async trigger(type, eventOverrides = {}) {
            const handlers = listeners.get(type) || [];
            const event = { type, target: this, ...eventOverrides };
            for (const handler of handlers) {
                await handler(event);
            }
        },
    };
}

function createExperienceFlowStorageMock(initial = {}) {
    const calls = {
        markGuidedEntry: [],
        markGuidedCompleted: [],
        markGuidedInterrupted: [],
    };
    let flow = {
        hasCompletedInitialGuidedFlow: false,
        lastGuidedEntryDate: null,
        lastGuidedCompletedDate: null,
        lastGuidedStatus: 'not_started',
        ...initial,
    };

    return {
        calls,
        getExperienceFlow() {
            return { ...flow };
        },
        shouldEnterGuidedFlow(dateKey) {
            const firstEverOpen = !flow.hasCompletedInitialGuidedFlow && !flow.lastGuidedEntryDate;
            if (firstEverOpen) {
                return true;
            }
            return flow.lastGuidedEntryDate !== dateKey;
        },
        markGuidedEntry(dateKey) {
            calls.markGuidedEntry.push(dateKey);
            flow = {
                ...flow,
                lastGuidedEntryDate: dateKey,
                lastGuidedStatus: 'in_progress',
            };
            return { ...flow };
        },
        markGuidedCompleted(dateKey) {
            calls.markGuidedCompleted.push(dateKey);
            flow = {
                ...flow,
                hasCompletedInitialGuidedFlow: true,
                lastGuidedEntryDate: dateKey,
                lastGuidedCompletedDate: dateKey,
                lastGuidedStatus: 'completed',
            };
            return { ...flow };
        },
        markGuidedInterrupted(dateKey) {
            calls.markGuidedInterrupted.push(dateKey);
            if (flow.lastGuidedStatus === 'in_progress') {
                flow = {
                    ...flow,
                    lastGuidedEntryDate: flow.lastGuidedEntryDate || dateKey,
                    lastGuidedStatus: 'interrupted',
                };
            }
            return { ...flow };
        },
        snapshot() {
            return { ...flow };
        },
    };
}

function createGuidedDocument() {
    const documentObj = createMockDocument([
        'app',
        'graph-layout',
        'guided-flow-shell',
        'guided-step-indicator',
        'guided-step-title',
        'guided-step-description',
        'guided-cta-wrap',
        'guided-next-btn',
        'guided-open-explore-btn',
        'guided-resume-banner',
        'continue-guided-btn',
        'restart-guided-flow-btn',
        'defense-checkin',
        'causal-graph',
        'activity-feed-panel',
    ]);

    documentObj.getElementById('guided-flow-shell').classList.add('hidden');
    documentObj.getElementById('guided-cta-wrap').classList.add('hidden');
    documentObj.getElementById('guided-resume-banner').classList.add('hidden');

    return documentObj;
}

function createController({
    storageApi,
    nowIso = '2026-02-21T09:00:00.000Z',
    documentObj = createGuidedDocument(),
} = {}) {
    const windowObj = createWindowMock();
    const controller = initExperienceFlow({
        storageApi,
        documentObj,
        windowObj,
        nowFn: () => new Date(nowIso),
    });

    return { controller, documentObj, windowObj };
}

test('first-ever launch enters guided outcomes step', () => {
    const storageApi = createExperienceFlowStorageMock();
    const { controller } = createController({ storageApi });

    assert.equal(controller.getState().activeMode, 'guided');
    assert.equal(controller.getState().guidedStep, 'outcomes');
    assert.deepEqual(storageApi.calls.markGuidedEntry, ['2026-02-21']);
});

test('same-day reopen after completion starts directly in explore mode', () => {
    const storageApi = createExperienceFlowStorageMock({
        hasCompletedInitialGuidedFlow: true,
        lastGuidedEntryDate: '2026-02-21',
        lastGuidedCompletedDate: '2026-02-21',
        lastGuidedStatus: 'completed',
    });
    const { controller } = createController({ storageApi });

    assert.equal(controller.getState().activeMode, 'explore');
    assert.equal(controller.getState().guidedStep, null);
    assert.deepEqual(storageApi.calls.markGuidedEntry, []);
});

test('next-day first open enters guided flow again', () => {
    const storageApi = createExperienceFlowStorageMock({
        hasCompletedInitialGuidedFlow: true,
        lastGuidedEntryDate: '2026-02-20',
        lastGuidedCompletedDate: '2026-02-20',
        lastGuidedStatus: 'completed',
    });
    const { controller } = createController({ storageApi });

    assert.equal(controller.getState().activeMode, 'guided');
    assert.equal(controller.getState().guidedStep, 'outcomes');
    assert.deepEqual(storageApi.calls.markGuidedEntry, ['2026-02-21']);
});

test('mid-flow interruption causes same-day reopen to land in explore with resume banner', () => {
    const storageApi = createExperienceFlowStorageMock();
    const initial = createController({ storageApi });

    initial.controller.dispatch('APP_BACKGROUND_OR_TERMINATE');
    assert.equal(storageApi.snapshot().lastGuidedStatus, 'interrupted');

    const reopened = createController({
        storageApi,
        nowIso: '2026-02-21T16:45:00.000Z',
    });

    assert.equal(reopened.controller.getState().activeMode, 'explore');
    assert.equal(reopened.documentObj.getElementById('guided-resume-banner').classList.contains('hidden'), false);
});

test('CTA progression is strictly outcomes to situation to inputs to done', async () => {
    const storageApi = createExperienceFlowStorageMock();
    const { controller, documentObj } = createController({ storageApi });
    const cta = documentObj.getElementById('guided-next-btn');

    assert.equal(controller.getState().guidedStep, 'outcomes');
    await cta.trigger('click');
    assert.equal(controller.getState().guidedStep, 'situation');
    await cta.trigger('click');
    assert.equal(controller.getState().guidedStep, 'inputs');
    await cta.trigger('click');
    assert.equal(controller.getState().activeMode, 'explore');
});

test('situation step activates graph-focused phase markers', async () => {
    const storageApi = createExperienceFlowStorageMock();
    const { controller, documentObj } = createController({ storageApi });
    const cta = documentObj.getElementById('guided-next-btn');

    await cta.trigger('click');

    const app = documentObj.getElementById('app');
    assert.equal(controller.getState().guidedStep, 'situation');
    assert.equal(app.classList.contains('guided-step-situation'), true);
    assert.equal(app.dataset.guidedStep, 'situation');
    assert.ok(documentObj.getElementById('causal-graph'));
});

test('done marks guided completion date and status', async () => {
    const storageApi = createExperienceFlowStorageMock();
    const { documentObj } = createController({ storageApi });
    const cta = documentObj.getElementById('guided-next-btn');

    await cta.trigger('click');
    await cta.trigger('click');
    await cta.trigger('click');

    const flow = storageApi.snapshot();
    assert.equal(flow.lastGuidedCompletedDate, '2026-02-21');
    assert.equal(flow.lastGuidedStatus, 'completed');
});

test('AI mutate gate is disabled during guided flow and enabled in explore mode', async () => {
    const storageApi = createExperienceFlowStorageMock();
    const { controller, documentObj } = createController({ storageApi });
    const cta = documentObj.getElementById('guided-next-btn');

    assert.equal(controller.canMutateWithAi(), false);
    assert.equal(documentObj.getElementById('app').dataset.aiMutationsAllowed, 'false');

    await cta.trigger('click');
    await cta.trigger('click');
    await cta.trigger('click');

    assert.equal(controller.canMutateWithAi(), true);
    assert.equal(documentObj.getElementById('app').dataset.aiMutationsAllowed, 'true');
});

test('guided indicator and CTA labels match progression for screen reader order', async () => {
    const storageApi = createExperienceFlowStorageMock();
    const { documentObj } = createController({ storageApi });
    const cta = documentObj.getElementById('guided-next-btn');
    const indicator = documentObj.getElementById('guided-step-indicator');

    assert.equal(indicator.textContent, 'Step 1 of 3');
    assert.equal(cta.textContent, 'Go to Graph');

    await cta.trigger('click');
    assert.equal(indicator.textContent, 'Step 2 of 3');
    assert.equal(cta.textContent, 'What can I do?');

    await cta.trigger('click');
    assert.equal(indicator.textContent, 'Step 3 of 3');
    assert.equal(cta.textContent, 'Done');
});

test('restart guided button re-enters outcomes flow from explore mode', async () => {
    const storageApi = createExperienceFlowStorageMock();
    const { controller, documentObj } = createController({ storageApi });
    const cta = documentObj.getElementById('guided-next-btn');
    const restartBtn = documentObj.getElementById('restart-guided-flow-btn');

    await cta.trigger('click');
    await cta.trigger('click');
    await cta.trigger('click');

    assert.equal(controller.getState().activeMode, 'explore');

    await restartBtn.trigger('click');

    assert.equal(controller.getState().activeMode, 'guided');
    assert.equal(controller.getState().guidedStep, 'outcomes');
    assert.equal(storageApi.calls.markGuidedEntry.length, 2);
    assert.equal(storageApi.calls.markGuidedEntry[1], '2026-02-21');
});
