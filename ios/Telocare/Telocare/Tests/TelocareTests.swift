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
        #expect(patch?.activeInterventions == nil)
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

    @Test func doseIncrementPersistsDailyDoseProgressPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            snapshot: doseSnapshot(),
            initialDailyDoseProgress: ["2026-02-21": ["water_intake": 500]],
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.incrementInputDose("water_intake")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(patch?.dailyDoseProgress?["2026-02-21"]?["water_intake"] == 600)
    }

    @Test func doseUpdateSettingsPersistsPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            snapshot: doseSnapshot(),
            initialInterventionDoseSettings: ["water_intake": DoseSettings(dailyGoal: 3000, increment: 100)],
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.updateDoseSettings("water_intake", dailyGoal: 3500, increment: 150)

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(patch?.interventionDoseSettings?["water_intake"]?.dailyGoal == 3500)
        #expect(patch?.interventionDoseSettings?["water_intake"]?.increment == 150)
    }

    @Test func connectAppleHealthPersistsConnectionPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            snapshot: doseSnapshotWithAppleHealth(connected: false),
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            },
            appleHealthDoseService: MockAppleHealthDoseService(
                requestAuthorization: { _ in },
                fetchValue: { _, _, _ in 900 }
            )
        )

        harness.viewModel.connectInputToAppleHealth("water_intake")

        await waitUntil { await patchRecorder.count() >= 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(patch?.appleHealthConnections?["water_intake"]?.isConnected == true)
    }

    @Test func refreshAppleHealthUsesMaxValueOverManualDose() async {
        let harness = AppViewModelHarness(
            snapshot: doseSnapshotWithAppleHealth(connected: true),
            appleHealthDoseService: MockAppleHealthDoseService(
                fetchValue: { _, _, _ in 1200 }
            )
        )

        await harness.viewModel.refreshAppleHealth(for: "water_intake")

        let input = harness.viewModel.snapshot.inputs.first(where: { $0.id == "water_intake" })
        #expect(input?.doseState?.manualValue == 500)
        #expect(input?.doseState?.healthValue == 1200)
        #expect(input?.doseState?.value == 1200)
        #expect(input?.appleHealthState?.syncStatus == .synced)
    }

    @Test func refreshAppleHealthNoDataKeepsManualDose() async {
        let harness = AppViewModelHarness(
            snapshot: doseSnapshotWithAppleHealth(connected: true),
            appleHealthDoseService: MockAppleHealthDoseService(
                fetchValue: { _, _, _ in nil }
            )
        )

        await harness.viewModel.refreshAppleHealth(for: "water_intake")

        let input = harness.viewModel.snapshot.inputs.first(where: { $0.id == "water_intake" })
        #expect(input?.doseState?.manualValue == 500)
        #expect(input?.doseState?.healthValue == nil)
        #expect(input?.doseState?.value == 500)
        #expect(input?.appleHealthState?.syncStatus == .noData)
    }

    @Test func inputActivationTogglePersistsActiveInterventionsPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.toggleInputActive("ppi")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()

        #expect(patch?.activeInterventions?.contains("ppi") == true)
        #expect(patch?.dailyCheckIns == nil)
        #expect(patch?.morningStates == nil)
    }

    @Test func inputActivationToggleFailureRevertsState() async {
        let harness = AppViewModelHarness(
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        let before = harness.viewModel.snapshot.inputs.first(where: { $0.id == "ppi" })
        harness.viewModel.toggleInputActive("ppi")

        await waitUntil { harness.viewModel.exploreFeedback.contains("Could not save tracking state") }
        let after = harness.viewModel.snapshot.inputs.first(where: { $0.id == "ppi" })

        #expect(before?.isActive == after?.isActive)
        #expect(harness.viewModel.exploreFeedback == "Could not save tracking state for PPI. Reverted.")
        #expect(harness.recorder.messages.last == "Could not save tracking state for PPI. Reverted.")
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
        #expect(patch?.activeInterventions == nil)
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

    private func doseSnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            outcomes: OutcomeSummary(
                shieldScore: 0,
                burdenTrendPercent: 0,
                topContributor: "None",
                confidence: "Low",
                burdenProgress: 0
            ),
            outcomeRecords: [],
            outcomesMetadata: .empty,
            situation: SituationSummary(
                focusedNode: "RMMA",
                tier: "Tier 7",
                visibleHotspots: 1,
                topSource: "None"
            ),
            inputs: [
                InputStatus(
                    id: "water_intake",
                    name: "Water Intake",
                    trackingMode: .dose,
                    statusText: "500/3000 ml today (17%)",
                    completion: 0.1667,
                    isCheckedToday: false,
                    doseState: InputDoseState(
                        value: 500,
                        goal: 3000,
                        increment: 100,
                        unit: .milliliters
                    ),
                    graphNodeID: "HYDRATION",
                    classificationText: nil,
                    isActive: false,
                    evidenceLevel: nil,
                    evidenceSummary: nil,
                    detailedDescription: nil,
                    citationIDs: [],
                    externalLink: nil,
                    appleHealthState: nil
                )
            ]
        )
    }

    private func doseSnapshotWithAppleHealth(connected: Bool) -> DashboardSnapshot {
        DashboardSnapshot(
            outcomes: OutcomeSummary(
                shieldScore: 0,
                burdenTrendPercent: 0,
                topContributor: "None",
                confidence: "Low",
                burdenProgress: 0
            ),
            outcomeRecords: [],
            outcomesMetadata: .empty,
            situation: SituationSummary(
                focusedNode: "RMMA",
                tier: "Tier 7",
                visibleHotspots: 1,
                topSource: "None"
            ),
            inputs: [
                InputStatus(
                    id: "water_intake",
                    name: "Water Intake",
                    trackingMode: .dose,
                    statusText: "500/3000 ml today (17%)",
                    completion: 0.1667,
                    isCheckedToday: false,
                    doseState: InputDoseState(
                        manualValue: 500,
                        healthValue: nil,
                        goal: 3000,
                        increment: 100,
                        unit: .milliliters
                    ),
                    graphNodeID: "HYDRATION",
                    classificationText: nil,
                    isActive: false,
                    evidenceLevel: nil,
                    evidenceSummary: nil,
                    detailedDescription: nil,
                    citationIDs: [],
                    externalLink: nil,
                    appleHealthState: InputAppleHealthState(
                        available: true,
                        connected: connected,
                        syncStatus: connected ? .synced : .disconnected,
                        todayHealthValue: nil,
                        lastSyncAt: nil,
                        config: AppleHealthConfig(
                            identifier: .dietaryWater,
                            aggregation: .cumulativeSum,
                            dayAttribution: .localDay
                        )
                    )
                )
            ]
        )
    }
}

@MainActor
private struct AppViewModelHarness {
    let viewModel: AppViewModel
    let recorder: AnnouncementRecorder

    init(
        snapshot: DashboardSnapshot = InMemoryDashboardRepository().loadDashboardSnapshot(),
        initialExperienceFlow: ExperienceFlow = .empty,
        initialDailyCheckIns: [String: [String]] = [:],
        initialDailyDoseProgress: [String: [String: Double]] = [:],
        initialInterventionDoseSettings: [String: DoseSettings] = [:],
        initialAppleHealthConnections: [String: AppleHealthConnection] = [:],
        initialMorningStates: [MorningState] = [],
        initialActiveInterventions: [String] = [],
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true },
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService()
    ) {
        let recorder = AnnouncementRecorder()
        let announcer = AccessibilityAnnouncer { message in
            recorder.messages.append(message)
        }
        self.recorder = recorder
        viewModel = AppViewModel(
            snapshot: snapshot,
            graphData: CanonicalGraphLoader.loadGraphOrFallback(),
            initialExperienceFlow: initialExperienceFlow,
            initialDailyCheckIns: initialDailyCheckIns,
            initialDailyDoseProgress: initialDailyDoseProgress,
            initialInterventionDoseSettings: initialInterventionDoseSettings,
            initialAppleHealthConnections: initialAppleHealthConnections,
            initialMorningStates: initialMorningStates,
            initialActiveInterventions: initialActiveInterventions,
            persistUserDataPatch: persistUserDataPatch,
            appleHealthDoseService: appleHealthDoseService,
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
