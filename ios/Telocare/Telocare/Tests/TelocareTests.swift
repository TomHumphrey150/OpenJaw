import Foundation
import Testing
@testable import Telocare

struct AppViewModelTests {
    @Test func startsInGuidedOutcomes() {
        let harness = AppViewModelHarness()

        #expect(harness.viewModel.mode == .guided)
        #expect(harness.viewModel.guidedStep == .outcomes)
        #expect(harness.viewModel.snapshot.outcomes.shieldScore == 38)
        #expect(harness.viewModel.snapshot.outcomeRecords.isEmpty == false)
    }

    @Test func guidedSequenceTransitionsIntoExploreMode() {
        let harness = AppViewModelHarness()

        harness.viewModel.advanceFromOutcomes()
        harness.viewModel.advanceFromSituation()
        harness.viewModel.completeGuidedFlow()

        #expect(harness.viewModel.mode == .explore)
        #expect(harness.viewModel.guidedStep == .inputs)
        #expect(harness.viewModel.selectedExploreTab == .situation)
        #expect(
            harness.recorder.messages == [
                "Moved to Situation step.",
                "Moved to Inputs step.",
                "Guided flow complete. Explore mode unlocked.",
            ]
        )
    }

    @Test func outOfOrderGuidedActionsDoNotChangeState() {
        let harness = AppViewModelHarness()

        harness.viewModel.completeGuidedFlow()
        harness.viewModel.advanceFromSituation()

        #expect(harness.viewModel.mode == .guided)
        #expect(harness.viewModel.guidedStep == .outcomes)
        #expect(harness.recorder.messages.isEmpty)
    }

    @Test func exploreActionsUpdateFeedbackAndAnnouncement() {
        let harness = AppViewModelHarness()

        harness.viewModel.advanceFromOutcomes()
        harness.viewModel.advanceFromSituation()
        harness.viewModel.completeGuidedFlow()
        harness.viewModel.performExploreAction(.explainLinks)

        #expect(harness.viewModel.exploreFeedback == ExploreContextAction.explainLinks.detail)
        #expect(harness.recorder.messages.last == ExploreContextAction.explainLinks.announcement)
    }

    @Test func chatSubmissionRequiresTextAndClearsValidInput() {
        let harness = AppViewModelHarness()

        harness.viewModel.advanceFromOutcomes()
        harness.viewModel.advanceFromSituation()
        harness.viewModel.completeGuidedFlow()

        harness.viewModel.chatDraft = "   "
        harness.viewModel.submitChatPrompt()

        #expect(harness.viewModel.exploreFeedback == "Enter a request before sending.")

        harness.viewModel.chatDraft = "Add magnesium check-in."
        harness.viewModel.submitChatPrompt()

        #expect(harness.viewModel.chatDraft.isEmpty)
        #expect(harness.viewModel.exploreFeedback.contains("Add magnesium check-in."))
    }

    @Test func graphNodeSelectionUpdatesFocusedNodeSummary() {
        let harness = AppViewModelHarness()

        harness.viewModel.handleGraphEvent(.nodeSelected(id: "RMMA", label: "RMMA"))

        #expect(harness.viewModel.snapshot.situation.focusedNode == "RMMA")
        #expect(harness.viewModel.graphSelectionText.contains("Selected node"))
    }

    @Test func completedFlowTodayStartsInExploreMode() {
        let harness = AppViewModelHarness(
            initialExperienceFlow: ExperienceFlow(
                hasCompletedInitialGuidedFlow: true,
                lastGuidedEntryDate: "2026-02-21",
                lastGuidedCompletedDate: "2026-02-21",
                lastGuidedStatus: .completed
            ),
            nowProvider: {
                let calendar = Calendar(identifier: .gregorian)
                return calendar.date(from: DateComponents(year: 2026, month: 2, day: 21)) ?? Date()
            }
        )

        #expect(harness.viewModel.mode == .explore)
    }

    @Test func guidedFlowPersistsEntryCompletionAndInterruption() {
        let recorder = ExperienceFlowRecorder()
        let harness = AppViewModelHarness(
            initialExperienceFlow: .empty,
            persistExperienceFlow: { recorder.append($0) },
            nowProvider: {
                let calendar = Calendar(identifier: .gregorian)
                return calendar.date(from: DateComponents(year: 2026, month: 2, day: 21)) ?? Date()
            }
        )

        #expect(recorder.values.count == 1)
        #expect(recorder.values.first?.lastGuidedStatus == .inProgress)

        harness.viewModel.handleAppMovedToBackground()
        #expect(recorder.values.last?.lastGuidedStatus == .interrupted)

        harness.viewModel.advanceFromOutcomes()
        harness.viewModel.advanceFromSituation()
        harness.viewModel.completeGuidedFlow()

        #expect(recorder.values.last?.lastGuidedStatus == .completed)
    }
}

private struct AppViewModelHarness {
    let viewModel: AppViewModel
    let recorder: AnnouncementRecorder

    init(
        initialExperienceFlow: ExperienceFlow = .empty,
        persistExperienceFlow: @escaping (ExperienceFlow) -> Void = { _ in },
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let recorder = AnnouncementRecorder()
        let announcer = AccessibilityAnnouncer { message in
            recorder.messages.append(message)
        }
        self.recorder = recorder
        viewModel = AppViewModel(
            snapshot: InMemoryDashboardRepository().loadDashboardSnapshot(),
            graphData: CanonicalGraphLoader.loadGraphOrFallback(),
            initialExperienceFlow: initialExperienceFlow,
            persistExperienceFlow: persistExperienceFlow,
            nowProvider: nowProvider,
            accessibilityAnnouncer: announcer
        )
    }
}

private final class AnnouncementRecorder {
    var messages: [String] = []
}

private final class ExperienceFlowRecorder {
    private(set) var values: [ExperienceFlow] = []

    func append(_ value: ExperienceFlow) {
        values.append(value)
    }
}
