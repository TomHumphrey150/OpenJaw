import Foundation
import Testing
@testable import Telocare

struct AppViewModelTests {
    @Test func startsInExploreInputsTab() {
        let harness = AppViewModelHarness()

        #expect(harness.viewModel.mode == .explore)
        #expect(harness.viewModel.selectedExploreTab == .inputs)
        #expect(harness.viewModel.snapshot.outcomes.shieldScore == 38)
        #expect(harness.viewModel.snapshot.outcomeRecords.isEmpty == false)
    }

    @Test func selectingExploreTabUpdatesSelectionAndAnnouncement() {
        let harness = AppViewModelHarness()

        harness.viewModel.selectExploreTab(.situation)

        #expect(harness.viewModel.selectedExploreTab == .situation)
        #expect(harness.recorder.messages.last == "Situation tab selected.")
    }

    @Test func exploreActionsUpdateFeedbackAndAnnouncement() {
        let harness = AppViewModelHarness()

        harness.viewModel.performExploreAction(.explainLinks)

        #expect(harness.viewModel.exploreFeedback == ExploreContextAction.explainLinks.detail)
        #expect(harness.recorder.messages.last == ExploreContextAction.explainLinks.announcement)
    }

    @Test func chatSubmissionRequiresTextAndClearsValidInput() {
        let harness = AppViewModelHarness()

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

    @Test func morningOutcomesSavePersistsUpdatedState() {
        let stateRecorder = MorningStateRecorder()
        let harness = AppViewModelHarness(
            persistMorningStates: { stateRecorder.append($0) }
        )

        harness.viewModel.setMorningOutcomeValue(7, for: .globalSensation)
        harness.viewModel.setMorningOutcomeValue(4, for: .neckTightness)
        harness.viewModel.saveMorningOutcomes()

        #expect(stateRecorder.values.count == 1)
        #expect(stateRecorder.values.first?.count == 1)
        #expect(stateRecorder.values.first?.first?.nightId == "2026-02-21")
        #expect(stateRecorder.values.first?.first?.globalSensation == 7)
        #expect(stateRecorder.values.first?.first?.neckTightness == 4)
    }

    @Test func morningOutcomesRequireAtLeastOneValueBeforeSaving() {
        let stateRecorder = MorningStateRecorder()
        let harness = AppViewModelHarness(
            persistMorningStates: { stateRecorder.append($0) }
        )

        harness.viewModel.saveMorningOutcomes()

        #expect(stateRecorder.values.isEmpty)
        #expect(harness.viewModel.exploreFeedback == "Select at least one morning outcome before saving.")
    }
}

private struct AppViewModelHarness {
    let viewModel: AppViewModel
    let recorder: AnnouncementRecorder

    init(
        initialExperienceFlow: ExperienceFlow = .empty,
        persistExperienceFlow: @escaping (ExperienceFlow) -> Void = { _ in },
        initialMorningStates: [MorningState] = [],
        persistMorningStates: @escaping ([MorningState]) -> Void = { _ in }
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
            initialMorningStates: initialMorningStates,
            persistMorningStates: persistMorningStates,
            nowProvider: {
                let calendar = Calendar(identifier: .gregorian)
                return calendar.date(from: DateComponents(year: 2026, month: 2, day: 21)) ?? Date()
            },
            accessibilityAnnouncer: announcer
        )
    }
}

private final class AnnouncementRecorder {
    var messages: [String] = []
}

private final class MorningStateRecorder {
    private(set) var values: [[MorningState]] = []

    func append(_ value: [MorningState]) {
        values.append(value)
    }
}
