import Foundation
import Testing
@testable import Telocare

@MainActor
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

    @Test func inputCheckTogglePersistsDailyCheckInsPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            initialDailyCheckIns: ["2026-02-21": ["ppi"]],
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.toggleInputCheckedToday("bed_elevation")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()

        #expect(patch?.dailyCheckIns?["2026-02-21"]?.contains("bed_elevation") == true)
        #expect(patch?.hiddenInterventions == nil)
        #expect(patch?.morningStates == nil)
    }

    @Test func inputCheckToggleFailureRevertsState() async {
        let harness = AppViewModelHarness(
            initialDailyCheckIns: ["2026-02-21": ["ppi"]],
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        let before = harness.viewModel.snapshot.inputs.first(where: { $0.id == "bed_elevation" })
        harness.viewModel.toggleInputCheckedToday("bed_elevation")

        await waitUntil { harness.viewModel.exploreFeedback.contains("Could not save") }
        let after = harness.viewModel.snapshot.inputs.first(where: { $0.id == "bed_elevation" })

        #expect(before?.isCheckedToday == after?.isCheckedToday)
        #expect(harness.viewModel.exploreFeedback == "Could not save Bed Elevation check-in. Reverted.")
        #expect(harness.recorder.messages.last == "Could not save Bed Elevation check-in. Reverted.")
    }

    @Test func inputMuteTogglePersistsHiddenInterventionsPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.toggleInputHidden("ppi")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()

        #expect(patch?.hiddenInterventions?.contains("ppi") == true)
        #expect(patch?.dailyCheckIns == nil)
        #expect(patch?.morningStates == nil)
    }

    @Test func inputMuteToggleFailureRevertsState() async {
        let harness = AppViewModelHarness(
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        let before = harness.viewModel.snapshot.inputs.first(where: { $0.id == "ppi" })
        harness.viewModel.toggleInputHidden("ppi")

        await waitUntil { harness.viewModel.exploreFeedback.contains("Could not save mute state") }
        let after = harness.viewModel.snapshot.inputs.first(where: { $0.id == "ppi" })

        #expect(before?.isHidden == after?.isHidden)
        #expect(harness.viewModel.exploreFeedback == "Could not save mute state for PPI. Reverted.")
        #expect(harness.recorder.messages.last == "Could not save mute state for PPI. Reverted.")
    }

    @Test func morningOutcomeTapPersistsPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.setMorningOutcomeValue(7, for: .globalSensation)

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()

        #expect(patch?.morningStates?.first?.nightId == "2026-02-21")
        #expect(patch?.morningStates?.first?.globalSensation == 7)
        #expect(patch?.dailyCheckIns == nil)
        #expect(patch?.hiddenInterventions == nil)
    }

    @Test func morningOutcomeTapFailureRevertsState() async {
        let harness = AppViewModelHarness(
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        #expect(harness.viewModel.morningOutcomeSelection.value(for: .globalSensation) == nil)
        harness.viewModel.setMorningOutcomeValue(7, for: .globalSensation)

        await waitUntil { harness.viewModel.exploreFeedback == "Could not save morning outcomes. Reverted." }

        #expect(harness.viewModel.morningOutcomeSelection.value(for: .globalSensation) == nil)
        #expect(harness.recorder.messages.last == "Could not save morning outcomes. Reverted.")
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

@MainActor
private struct AppViewModelHarness {
    let viewModel: AppViewModel
    let recorder: AnnouncementRecorder

    init(
        initialExperienceFlow: ExperienceFlow = .empty,
        initialDailyCheckIns: [String: [String]] = [:],
        initialMorningStates: [MorningState] = [],
        initialHiddenInterventions: [String] = [],
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true }
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
            initialDailyCheckIns: initialDailyCheckIns,
            initialMorningStates: initialMorningStates,
            initialHiddenInterventions: initialHiddenInterventions,
            persistUserDataPatch: persistUserDataPatch,
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

private actor PatchRecorder {
    private var patches: [UserDataPatch] = []

    func record(_ patch: UserDataPatch) {
        patches.append(patch)
    }

    func count() -> Int {
        patches.count
    }

    func lastPatch() -> UserDataPatch? {
        patches.last
    }
}

private enum PatchFailure: Error {
    case writeFailed
}
