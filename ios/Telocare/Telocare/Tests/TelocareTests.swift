import Testing
@testable import Telocare

struct AppViewModelTests {
    @Test func startsInGuidedOutcomes() {
        let harness = AppViewModelHarness()

        #expect(harness.viewModel.mode == .guided)
        #expect(harness.viewModel.guidedStep == .outcomes)
        #expect(harness.viewModel.snapshot.outcomes.shieldScore == 38)
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
}

private struct AppViewModelHarness {
    let viewModel: AppViewModel
    let recorder: AnnouncementRecorder

    init() {
        let recorder = AnnouncementRecorder()
        let announcer = AccessibilityAnnouncer { message in
            recorder.messages.append(message)
        }
        self.recorder = recorder
        viewModel = AppViewModel(
            loadDashboardSnapshotUseCase: LoadDashboardSnapshotUseCase(repository: InMemoryDashboardRepository()),
            accessibilityAnnouncer: announcer
        )
    }
}

private final class AnnouncementRecorder {
    var messages: [String] = []
}
