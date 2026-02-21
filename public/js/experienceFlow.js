import {
    EXPERIENCE_FLOW_STATUS,
    getExperienceFlow,
    markGuidedCompleted,
    markGuidedEntry,
    markGuidedInterrupted,
    shouldEnterGuidedFlow,
} from './storage.js';

const GUIDED_STEPS = Object.freeze(['outcomes', 'situation', 'inputs']);
const GUIDED_STEP_METADATA = Object.freeze({
    outcomes: {
        title: 'Outcomes',
        description: 'Start with what changed so today starts from evidence instead of guesswork.',
        cta: 'Go to Graph',
        indicator: 'Step 1 of 3',
    },
    situation: {
        title: 'Graph',
        description: 'Review the graph to see the strongest links driving your current state.',
        cta: 'What can I do?',
        indicator: 'Step 2 of 3',
    },
    inputs: {
        title: 'What to do',
        description: 'Choose habits and check-ins that can change your trajectory.',
        cta: 'Done',
        indicator: 'Step 3 of 3',
    },
});

const EVENTS = Object.freeze({
    APP_OPEN: 'APP_OPEN',
    HYDRATION_COMPLETE: 'HYDRATION_COMPLETE',
    GUIDED_NEXT: 'GUIDED_NEXT',
    GUIDED_DONE: 'GUIDED_DONE',
    APP_BACKGROUND_OR_TERMINATE: 'APP_BACKGROUND_OR_TERMINATE',
    OPEN_EXPLORE: 'OPEN_EXPLORE',
});

const MODES = Object.freeze({
    GUIDED: 'guided',
    EXPLORE: 'explore',
});

const GUIDED_TRANSITION_MS = 280;

function toLocalDateKey(date) {
    const year = String(date.getFullYear());
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function stepIndex(step) {
    return GUIDED_STEPS.indexOf(step);
}

function safeCall(fn, fallbackValue) {
    try {
        return fn();
    } catch (_) {
        return fallbackValue;
    }
}

function removeClasses(element, classes) {
    if (!element || !element.classList) return;
    classes.forEach((className) => element.classList.remove(className));
}

function addClasses(element, classes) {
    if (!element || !element.classList) return;
    classes.forEach((className) => element.classList.add(className));
}

export function createExperienceFlowController({
    storageApi = {},
    documentObj = typeof document !== 'undefined' ? document : null,
    windowObj = typeof window !== 'undefined' ? window : null,
    nowFn = () => new Date(),
    setTimeoutFn = (callback, delay) => setTimeout(callback, delay),
    clearTimeoutFn = (id) => clearTimeout(id),
} = {}) {
    const elements = {
        app: documentObj?.getElementById('app') || null,
        graphLayout: documentObj?.getElementById('graph-layout') || null,
        guidedShell: documentObj?.getElementById('guided-flow-shell') || null,
        guidedIndicator: documentObj?.getElementById('guided-step-indicator') || null,
        guidedTitle: documentObj?.getElementById('guided-step-title') || null,
        guidedDescription: documentObj?.getElementById('guided-step-description') || null,
        guidedCtaWrap: documentObj?.getElementById('guided-cta-wrap') || null,
        guidedNextBtn: documentObj?.getElementById('guided-next-btn') || null,
        openExploreBtn: documentObj?.getElementById('guided-open-explore-btn') || null,
        resumeBanner: documentObj?.getElementById('guided-resume-banner') || null,
        resumeBannerBtn: documentObj?.getElementById('continue-guided-btn') || null,
        restartGuidedBtn: documentObj?.getElementById('restart-guided-flow-btn') || null,
    };

    const listeners = [];
    const sessionState = {
        activeMode: MODES.EXPLORE,
        guidedStep: null,
    };

    let hydrationComplete = false;
    let appOpen = false;
    let entryDecisionApplied = false;
    let transitionTimer = null;

    const api = {
        getExperienceFlow: storageApi.getExperienceFlow || getExperienceFlow,
        shouldEnterGuidedFlow: storageApi.shouldEnterGuidedFlow || shouldEnterGuidedFlow,
        markGuidedEntry: storageApi.markGuidedEntry || markGuidedEntry,
        markGuidedCompleted: storageApi.markGuidedCompleted || markGuidedCompleted,
        markGuidedInterrupted: storageApi.markGuidedInterrupted || markGuidedInterrupted,
    };

    function todayKey() {
        return toLocalDateKey(nowFn());
    }

    function currentFlow() {
        return safeCall(() => api.getExperienceFlow(), {
            hasCompletedInitialGuidedFlow: false,
            lastGuidedEntryDate: null,
            lastGuidedCompletedDate: null,
            lastGuidedStatus: EXPERIENCE_FLOW_STATUS.NOT_STARTED,
        });
    }

    function canMutateWithAi() {
        return sessionState.activeMode === MODES.EXPLORE;
    }

    function emitStateChange() {
        if (elements.app && elements.app.dataset) {
            elements.app.dataset.activeMode = sessionState.activeMode;
            elements.app.dataset.guidedStep = sessionState.guidedStep || '';
            elements.app.dataset.aiMutationsAllowed = canMutateWithAi() ? 'true' : 'false';
        }

        const customEventCtor = windowObj?.CustomEvent || globalThis.CustomEvent;
        if (!windowObj || typeof windowObj.dispatchEvent !== 'function' || typeof customEventCtor !== 'function') {
            return;
        }

        windowObj.dispatchEvent(new customEventCtor('openjaw:experience-flow-state', {
            detail: getState(),
        }));
    }

    function setGuidedTransitionAnimation() {
        if (!elements.graphLayout || !elements.graphLayout.classList) return;
        elements.graphLayout.classList.remove('guided-transition');
        if (typeof elements.graphLayout.offsetWidth === 'number') {
            void elements.graphLayout.offsetWidth;
        }
        elements.graphLayout.classList.add('guided-transition');
        if (transitionTimer) {
            clearTimeoutFn(transitionTimer);
        }
        transitionTimer = setTimeoutFn(() => {
            elements.graphLayout?.classList?.remove('guided-transition');
            transitionTimer = null;
        }, GUIDED_TRANSITION_MS);
    }

    function setAppClasses(mode, step = null) {
        const classNames = [
            'mode-guided',
            'mode-explore',
            'guided-step-outcomes',
            'guided-step-situation',
            'guided-step-inputs',
        ];
        removeClasses(elements.app, classNames);
        addClasses(elements.app, [`mode-${mode}`]);
        if (mode === MODES.GUIDED && step) {
            addClasses(elements.app, [`guided-step-${step}`]);
        }
    }

    function setGuidedUi(step) {
        const meta = GUIDED_STEP_METADATA[step];
        if (!meta) return;

        elements.guidedIndicator && (elements.guidedIndicator.textContent = meta.indicator);
        elements.guidedTitle && (elements.guidedTitle.textContent = meta.title);
        elements.guidedDescription && (elements.guidedDescription.textContent = meta.description);
        elements.guidedNextBtn && (elements.guidedNextBtn.textContent = meta.cta);

        elements.guidedShell?.classList?.remove('hidden');
        elements.guidedCtaWrap?.classList?.remove('hidden');
        elements.resumeBanner?.classList?.add('hidden');
    }

    function hideGuidedUi() {
        elements.guidedShell?.classList?.add('hidden');
        elements.guidedCtaWrap?.classList?.add('hidden');
    }

    function showResumeBanner() {
        elements.resumeBanner?.classList?.remove('hidden');
    }

    function hideResumeBanner() {
        elements.resumeBanner?.classList?.add('hidden');
    }

    function setGuidedStep(step, { animate = true } = {}) {
        sessionState.activeMode = MODES.GUIDED;
        sessionState.guidedStep = step;
        setAppClasses(MODES.GUIDED, step);
        setGuidedUi(step);
        if (animate) {
            setGuidedTransitionAnimation();
        }
        emitStateChange();
    }

    function enterExplore({ showInterruptedBanner = false } = {}) {
        sessionState.activeMode = MODES.EXPLORE;
        sessionState.guidedStep = null;
        setAppClasses(MODES.EXPLORE);
        hideGuidedUi();
        if (showInterruptedBanner) {
            showResumeBanner();
        } else {
            hideResumeBanner();
        }
        emitStateChange();
    }

    function shouldShowInterruptedBanner(flow, dateKey) {
        return flow.lastGuidedStatus === EXPERIENCE_FLOW_STATUS.INTERRUPTED &&
            flow.lastGuidedEntryDate === dateKey;
    }

    function decideEntryMode() {
        const dateKey = todayKey();
        const shouldGuide = safeCall(() => api.shouldEnterGuidedFlow(dateKey), true);

        if (shouldGuide) {
            safeCall(() => api.markGuidedEntry(dateKey));
            setGuidedStep('outcomes', { animate: false });
            return;
        }

        enterExplore({
            showInterruptedBanner: shouldShowInterruptedBanner(currentFlow(), dateKey),
        });
    }

    function maybeApplyEntryDecision() {
        if (!hydrationComplete || !appOpen || entryDecisionApplied) {
            return;
        }
        entryDecisionApplied = true;
        decideEntryMode();
    }

    function onGuidedNext() {
        if (sessionState.activeMode !== MODES.GUIDED || !sessionState.guidedStep) {
            return;
        }

        const currentStepIndex = stepIndex(sessionState.guidedStep);
        if (currentStepIndex < 0) return;
        if (currentStepIndex >= GUIDED_STEPS.length - 1) {
            dispatch(EVENTS.GUIDED_DONE);
            return;
        }

        const nextStep = GUIDED_STEPS[currentStepIndex + 1];
        setGuidedStep(nextStep);
    }

    function onGuidedDone() {
        const dateKey = todayKey();
        safeCall(() => api.markGuidedCompleted(dateKey));
        enterExplore({ showInterruptedBanner: false });
    }

    function onGuidedInterrupted() {
        if (sessionState.activeMode !== MODES.GUIDED || !sessionState.guidedStep) {
            return;
        }
        const dateKey = todayKey();
        safeCall(() => api.markGuidedInterrupted(dateKey));
        enterExplore({ showInterruptedBanner: true });
    }

    function onResumeGuidedFlow() {
        const dateKey = todayKey();
        safeCall(() => api.markGuidedEntry(dateKey));
        setGuidedStep('outcomes', { animate: true });
    }

    function dispatch(eventType) {
        switch (eventType) {
            case EVENTS.HYDRATION_COMPLETE: {
                hydrationComplete = true;
                maybeApplyEntryDecision();
                return getState();
            }
            case EVENTS.APP_OPEN: {
                appOpen = true;
                maybeApplyEntryDecision();
                return getState();
            }
            case EVENTS.GUIDED_NEXT: {
                onGuidedNext();
                return getState();
            }
            case EVENTS.GUIDED_DONE: {
                onGuidedDone();
                return getState();
            }
            case EVENTS.APP_BACKGROUND_OR_TERMINATE: {
                onGuidedInterrupted();
                return getState();
            }
            case EVENTS.OPEN_EXPLORE: {
                enterExplore({ showInterruptedBanner: false });
                return getState();
            }
            default: {
                return getState();
            }
        }
    }

    function addListener(target, eventName, handler) {
        if (!target || typeof target.addEventListener !== 'function') return;
        target.addEventListener(eventName, handler);
        listeners.push(() => {
            if (typeof target.removeEventListener === 'function') {
                target.removeEventListener(eventName, handler);
            }
        });
    }

    function bindUi() {
        addListener(elements.guidedNextBtn, 'click', () => dispatch(EVENTS.GUIDED_NEXT));
        addListener(elements.openExploreBtn, 'click', () => dispatch(EVENTS.OPEN_EXPLORE));
        addListener(elements.resumeBannerBtn, 'click', onResumeGuidedFlow);
        addListener(elements.restartGuidedBtn, 'click', onResumeGuidedFlow);

        addListener(documentObj, 'visibilitychange', () => {
            if (documentObj.visibilityState === 'hidden') {
                dispatch(EVENTS.APP_BACKGROUND_OR_TERMINATE);
            }
        });

        addListener(windowObj, 'pagehide', () => dispatch(EVENTS.APP_BACKGROUND_OR_TERMINATE));
        addListener(windowObj, 'beforeunload', () => dispatch(EVENTS.APP_BACKGROUND_OR_TERMINATE));
    }

    function getState() {
        return {
            activeMode: sessionState.activeMode,
            guidedStep: sessionState.guidedStep,
            guidedStepIndex: sessionState.guidedStep ? stepIndex(sessionState.guidedStep) : null,
            aiMutationsAllowed: canMutateWithAi(),
        };
    }

    function destroy() {
        listeners.forEach((remove) => remove());
        listeners.length = 0;
        if (transitionTimer) {
            clearTimeoutFn(transitionTimer);
            transitionTimer = null;
        }
    }

    bindUi();
    emitStateChange();

    return {
        EVENTS,
        dispatch,
        destroy,
        getState,
        canMutateWithAi,
        startGuided: onResumeGuidedFlow,
    };
}

export function initExperienceFlow(options = {}) {
    const controller = createExperienceFlowController(options);
    controller.dispatch(EVENTS.HYDRATION_COMPLETE);
    controller.dispatch(EVENTS.APP_OPEN);
    return controller;
}

export const EXPERIENCE_FLOW_EVENTS = EVENTS;
