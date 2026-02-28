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

    @Test func exploreTabTitlesUseCalmNaming() {
        #expect(ExploreTab.inputs.title == "Habits")
        #expect(ExploreTab.situation.title == "My Map")
        #expect(ExploreTab.outcomes.title == "Progress")
        #expect(ExploreTab.chat.title == "Guide")
    }

    @Test func selectingExploreTabUpdatesSelectionAndAnnouncement() {
        let harness = AppViewModelHarness()

        harness.viewModel.selectExploreTab(.situation)

        #expect(harness.viewModel.selectedExploreTab == .situation)
        #expect(harness.recorder.messages.last == "My Map tab selected.")
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

    @Test func graphNodeDeactivationTogglePersistsCustomDiagramPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated == nil)
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isExpanded == false)

        harness.viewModel.toggleGraphNodeDeactivated("RMMA")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated == true)
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isExpanded == false)
        #expect(
            patch?.customCausalDiagram?.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated == true
        )
        #expect(
            patch?.customCausalDiagram?.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isExpanded == false
        )
    }

    @Test func graphNodeDoubleTapTogglesExpansionAndPersistsPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "STRESS" })?.data.isExpanded == false)

        harness.viewModel.handleGraphEvent(.nodeDoubleTapped(id: "STRESS", label: "Stress"))

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()

        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "STRESS" })?.data.isExpanded == true)
        #expect(
            patch?.customCausalDiagram?.graphData.nodes.first(where: { $0.data.id == "STRESS" })?.data.isExpanded == true
        )
    }

    @Test func hierarchySeedsRespiratoryBranchForOsaAndUars() {
        let harness = AppViewModelHarness()

        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "OSA" })?.data.parentIds == nil)
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "OSA" })?.data.parentId == nil)
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "AIRWAY_OBS" })?.data.parentIds == ["OSA"])
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "AIRWAY_OBS" })?.data.parentId == "OSA")
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "NEG_PRESSURE" })?.data.parentIds == ["AIRWAY_OBS"]
        )
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "NEG_PRESSURE" })?.data.parentId == "AIRWAY_OBS"
        )
    }

    @Test func hierarchySeedsExternalTriggerMultiParentMembership() {
        let harness = AppViewModelHarness()

        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "CAFFEINE" })?.data.parentIds
                == ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"]
        )
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "ALCOHOL" })?.data.parentIds
                == ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"]
        )
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "SMOKING" })?.data.parentIds
                == ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"]
        )
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "SSRI" })?.data.parentIds
                == ["EXTERNAL_TRIGGERS", "RMMA"]
        )
    }

    @Test func hierarchyRemapsLegacyOsaParentAssignments() {
        let legacyGraph = CausalGraphData(
            nodes: [
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "OSA",
                        label: "Sleep Apnea / UARS",
                        styleClass: "moderate",
                        confirmed: "no",
                        tier: nil,
                        tooltip: nil,
                        parentId: "GERD"
                    )
                ),
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "AIRWAY_OBS",
                        label: "Airway Obstruction",
                        styleClass: "mechanism",
                        confirmed: "no",
                        tier: nil,
                        tooltip: nil,
                        parentId: "GERD"
                    )
                ),
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "NEG_PRESSURE",
                        label: "Negative Pressure",
                        styleClass: "mechanism",
                        confirmed: "no",
                        tier: nil,
                        tooltip: nil,
                        parentId: "GERD"
                    )
                ),
            ],
            edges: []
        )

        let harness = AppViewModelHarness(graphData: legacyGraph)

        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "OSA" })?.data.parentIds == nil)
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "OSA" })?.data.parentId == nil)
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "AIRWAY_OBS" })?.data.parentIds == ["OSA"])
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "AIRWAY_OBS" })?.data.parentId == "OSA")
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "NEG_PRESSURE" })?.data.parentIds == ["AIRWAY_OBS"]
        )
        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "NEG_PRESSURE" })?.data.parentId == "AIRWAY_OBS"
        )
    }

    @Test func graphNodeDeactivationPreservesSeededParentMetadata() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.toggleGraphNodeDeactivated("CAFFEINE")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()

        #expect(
            harness.viewModel.graphData.nodes.first(where: { $0.data.id == "CAFFEINE" })?.data.parentIds
                == ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"]
        )
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "CAFFEINE" })?.data.parentId == "EXTERNAL_TRIGGERS")
        #expect(
            patch?.customCausalDiagram?.graphData.nodes.first(where: { $0.data.id == "CAFFEINE" })?.data.parentIds
                == ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"]
        )
        #expect(
            patch?.customCausalDiagram?.graphData.nodes.first(where: { $0.data.id == "CAFFEINE" })?.data.parentId == "EXTERNAL_TRIGGERS"
        )
    }

    @Test func graphEdgeDeactivationTogglePersistsCustomDiagramPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.toggleGraphEdgeDeactivated(
            sourceID: "STRESS",
            targetID: "SLEEP_DEP",
            label: "hyperarousal",
            edgeType: "forward"
        )

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(
            harness.viewModel.graphData.edges.first {
                $0.data.source == "STRESS"
                    && $0.data.target == "SLEEP_DEP"
                    && $0.data.label == "hyperarousal"
                    && $0.data.edgeType == "forward"
            }?.data.isDeactivated == true
        )
        #expect(
            patch?.customCausalDiagram?.graphData.edges.first {
                $0.data.source == "STRESS"
                    && $0.data.target == "SLEEP_DEP"
                    && $0.data.label == "hyperarousal"
                    && $0.data.edgeType == "forward"
            }?.data.isDeactivated == true
        )
    }

    @Test func graphDeactivationFailureRevertsState() async {
        let harness = AppViewModelHarness(
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        let before = harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated

        harness.viewModel.toggleGraphNodeDeactivated("RMMA")

        await waitUntil { harness.viewModel.exploreFeedback.contains("Could not save") }
        let after = harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated
        #expect(before == after)
        #expect(harness.viewModel.exploreFeedback.contains("Reverted."))
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
        #expect(patch?.interventionCompletionEvents?.count == 1)
        #expect(patch?.interventionCompletionEvents?.first?.interventionId == "bed_elevation")
        #expect(patch?.interventionCompletionEvents?.first?.source == .binaryCheck)
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
        #expect(before?.completionEvents == after?.completionEvents)
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
        #expect(patch?.interventionCompletionEvents?.count == 1)
        #expect(patch?.interventionCompletionEvents?.first?.interventionId == "water_intake")
        #expect(patch?.interventionCompletionEvents?.first?.source == .doseIncrement)
    }

    @Test func uncheckAndDoseUndoKeepExistingCompletionEvents() async {
        let existingEvent = InterventionCompletionEvent(
            interventionId: "ppi",
            occurredAt: "2026-02-20T08:00:00Z",
            source: .binaryCheck
        )
        let doseEvent = InterventionCompletionEvent(
            interventionId: "water_intake",
            occurredAt: "2026-02-20T08:05:00Z",
            source: .doseIncrement
        )

        let checkPatchRecorder = PatchRecorder()
        let checkHarness = AppViewModelHarness(
            initialDailyCheckIns: ["2026-02-21": ["ppi"]],
            initialInterventionCompletionEvents: [existingEvent],
            persistUserDataPatch: { patch in
                await checkPatchRecorder.record(patch)
                return true
            }
        )

        checkHarness.viewModel.toggleInputCheckedToday("ppi")

        await waitUntil { await checkPatchRecorder.count() == 1 }
        let checkPatch = await checkPatchRecorder.lastPatch()
        #expect(checkPatch?.interventionCompletionEvents == [existingEvent])
        #expect(checkHarness.viewModel.snapshot.inputs.first(where: { $0.id == "ppi" })?.completionEvents == [existingEvent])

        let dosePatchRecorder = PatchRecorder()
        let doseHarness = AppViewModelHarness(
            snapshot: doseSnapshot(),
            initialDailyDoseProgress: ["2026-02-21": ["water_intake": 500]],
            initialInterventionCompletionEvents: [doseEvent],
            persistUserDataPatch: { patch in
                await dosePatchRecorder.record(patch)
                return true
            }
        )

        doseHarness.viewModel.decrementInputDose("water_intake")
        await waitUntil { await dosePatchRecorder.count() == 1 }
        let decrementPatch = await dosePatchRecorder.lastPatch()
        #expect(decrementPatch?.interventionCompletionEvents == [doseEvent])

        doseHarness.viewModel.resetInputDose("water_intake")
        await waitUntil { await dosePatchRecorder.count() == 2 }
        let resetPatch = await dosePatchRecorder.lastPatch()
        #expect(resetPatch?.interventionCompletionEvents == [doseEvent])
    }

    @Test func doseIncrementFailureRevertsCompletionEvents() async {
        let harness = AppViewModelHarness(
            snapshot: doseSnapshot(),
            initialDailyDoseProgress: ["2026-02-21": ["water_intake": 500]],
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        #expect(harness.viewModel.snapshot.inputs.first(where: { $0.id == "water_intake" })?.completionEvents.isEmpty == true)

        harness.viewModel.incrementInputDose("water_intake")

        await waitUntil { harness.viewModel.exploreFeedback.contains("Could not save dose progress") }
        #expect(harness.viewModel.snapshot.inputs.first(where: { $0.id == "water_intake" })?.completionEvents.isEmpty == true)
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

    @Test func refreshAppleHealthPersistsConnectionsAndDailyDoseProgressPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            snapshot: doseSnapshotWithAppleHealth(connected: true),
            initialDailyDoseProgress: ["2026-02-21": ["water_intake": 500]],
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            },
            appleHealthDoseService: MockAppleHealthDoseService(
                requestAuthorization: { _ in },
                fetchValue: { _, _, _ in 1200 }
            )
        )

        await harness.viewModel.refreshAppleHealth(for: "water_intake", trigger: .manual)

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(patch?.appleHealthConnections?["water_intake"]?.lastSyncStatus == .synced)
        #expect(patch?.dailyDoseProgress?["2026-02-21"]?["water_intake"] == 1200)
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

    @Test func automaticRefreshSuppressesNoDataAnnouncementButManualAnnounces() async {
        let harness = AppViewModelHarness(
            snapshot: doseSnapshotWithAppleHealth(connected: true),
            appleHealthDoseService: MockAppleHealthDoseService(
                requestAuthorization: { _ in },
                fetchValue: { _, _, _ in nil }
            )
        )

        await harness.viewModel.refreshAppleHealth(for: "water_intake", trigger: .automatic)
        #expect(harness.recorder.messages.isEmpty)

        await harness.viewModel.refreshAppleHealth(for: "water_intake", trigger: .manual)
        #expect(harness.recorder.messages.last == "No Apple Health data for Water Intake today. Using app entries.")
    }

    @Test func automaticRefreshFailureAnnouncesAndPersistsFailedStatus() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            snapshot: doseSnapshotWithAppleHealth(connected: true),
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            },
            appleHealthDoseService: MockAppleHealthDoseService(
                requestAuthorization: { _ in
                    throw PatchFailure.writeFailed
                }
            )
        )

        await harness.viewModel.refreshAppleHealth(for: "water_intake", trigger: .automatic)

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(patch?.appleHealthConnections?["water_intake"]?.lastSyncStatus == .failed)
        #expect(harness.recorder.messages.last == "Could not refresh Apple Health for Water Intake.")
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

    @Test func morningQuestionnaireDefaultsToLegacyFieldsForUnconfiguredUsers() {
        let harness = AppViewModelHarness()

        #expect(harness.viewModel.morningCheckInFields == MorningOutcomeField.legacyFields)
        #expect(harness.viewModel.requiredMorningCheckInFields == MorningOutcomeField.legacyFields)
        #expect(
            harness.viewModel.morningTrendMetricOptions
                == [.composite] + MorningTrendMetric.legacyFieldMetrics
        )
    }

    @Test func morningQuestionnaireConfigRestrictsFieldsAndSavesConfiguredValues() async {
        let patchRecorder = PatchRecorder()
        let questionnaire = MorningQuestionnaire(
            enabledFields: [
                .neckTightness,
                .jawSoreness,
                .earFullness,
                .stressLevel,
                .morningHeadache,
                .dryMouth,
            ],
            requiredFields: [
                .neckTightness,
                .jawSoreness,
                .earFullness,
                .stressLevel,
                .morningHeadache,
                .dryMouth,
            ]
        )
        let harness = AppViewModelHarness(
            initialMorningQuestionnaire: questionnaire,
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        #expect(
            harness.viewModel.morningCheckInFields == [
                .neckTightness,
                .jawSoreness,
                .earFullness,
                .stressLevel,
                .morningHeadache,
                .dryMouth,
            ]
        )
        #expect(harness.viewModel.requiredMorningCheckInFields == harness.viewModel.morningCheckInFields)
        #expect(
            harness.viewModel.morningTrendMetricOptions == [
                .composite,
                .neckTightness,
                .jawSoreness,
                .earFullness,
                .stressLevel,
                .morningHeadache,
                .dryMouth,
            ]
        )

        harness.viewModel.setMorningOutcomeValue(7, for: .globalSensation)
        #expect(await patchRecorder.count() == 0)

        harness.viewModel.setMorningOutcomeValue(8, for: .morningHeadache)
        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(patch?.morningStates?.first?.morningHeadache == 8)
        #expect(patch?.morningStates?.first?.globalSensation == nil)
    }

    @Test func museSessionFlowSavesNightOutcomePatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            initialNightOutcomes: [
                NightOutcome(
                    nightId: "2026-02-20",
                    microArousalCount: 9,
                    microArousalRatePerHour: 1.8,
                    confidence: 0.7,
                    totalSleepMinutes: 360,
                    source: "wearable",
                    createdAt: "2026-02-20T07:30:00Z"
                )
            ],
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            },
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }

        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }

        await startMuseRecordingWithFitOverride(harness.viewModel)

        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museCanSaveNightOutcome }

        harness.viewModel.saveMuseNightOutcome()
        await waitUntil { await patchRecorder.count() == 1 }

        let patch = await patchRecorder.lastPatch()
        let latestNight = patch?.nightOutcomes?.first(where: { $0.nightId == "2026-02-21" })
        #expect(latestNight?.microArousalCount == 6)
        #expect(latestNight?.microArousalRatePerHour == 2)
        #expect(latestNight?.source == "muse_athena_heuristic_v1")
        #expect(harness.viewModel.museCanSaveNightOutcome == false)
    }

    @Test func museNightOutcomeSaveRequiresMinimumTwoHours() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            },
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-90 * 60),
                        endedAt: endDate,
                        microArousalCount: 4,
                        confidence: 0.7,
                        totalSleepMinutes: 90
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)
        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museRecordingSummary != nil }

        #expect(harness.viewModel.museCanSaveNightOutcome == false)
        harness.viewModel.saveMuseNightOutcome()

        await waitUntil { harness.viewModel.museSessionFeedback.contains("2 hours") }
        #expect(await patchRecorder.count() == 0)
    }

    @Test func museStartRecordingOpensFitCalibration() async {
        let harness = AppViewModelHarness()

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }

        harness.viewModel.startMuseRecording()

        #expect(harness.viewModel.isMuseFitCalibrationPresented == true)
        #expect(harness.viewModel.museCanStopRecording == false)
        #expect(harness.viewModel.museSessionFeedback.contains("Fit calibration opened"))

        harness.viewModel.dismissMuseFitCalibration()
        #expect(harness.viewModel.isMuseFitCalibrationPresented == false)
    }

    @Test func museFitReadyPathRequiresTwentySecondsBeforeReadyStart() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180,
                        fitGuidance: .good
                    )
                },
                fitDiagnosticsSnapshot: { _ in
                    MuseLiveDiagnostics(
                        elapsedSeconds: 10,
                        signalConfidence: 0.9,
                        awakeLikelihood: 0.2,
                        headbandOnCoverage: 0.95,
                        qualityGateCoverage: 0.88,
                        fitGuidance: .good,
                        rawDataPacketCount: 500,
                        rawArtifactPacketCount: 20,
                        parsedPacketCount: 520,
                        droppedPacketCount: 0,
                        droppedDataPacketTypeCounts: [:],
                        lastPacketAgeSeconds: 0.2,
                        fitReadiness: MuseFitReadinessSnapshot(
                            isReady: true,
                            primaryBlocker: nil,
                            blockers: [],
                            goodChannelCount: 4,
                            hsiGoodChannelCount: 4
                        ),
                        sensorStatuses: [
                            MuseSensorFitStatus(
                                sensor: .eeg1,
                                isGood: true,
                                hsiPrecision: 1,
                                passesIsGood: true,
                                passesHsi: true
                            ),
                            MuseSensorFitStatus(
                                sensor: .eeg2,
                                isGood: true,
                                hsiPrecision: 1,
                                passesIsGood: true,
                                passesHsi: true
                            ),
                            MuseSensorFitStatus(
                                sensor: .eeg3,
                                isGood: true,
                                hsiPrecision: 1,
                                passesIsGood: true,
                                passesHsi: true
                            ),
                            MuseSensorFitStatus(
                                sensor: .eeg4,
                                isGood: true,
                                hsiPrecision: 1,
                                passesIsGood: true,
                                passesHsi: true
                            ),
                        ],
                        droppedPacketTypes: []
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        harness.viewModel.startMuseRecording()

        #expect(harness.viewModel.museCanStartRecordingFromFitCalibration == false)
        harness.viewModel.startMuseRecordingFromFitCalibration()
        #expect(harness.viewModel.museCanStopRecording == false)

        await waitUntil { harness.viewModel.museCanStartRecordingFromFitCalibration }
        #expect(harness.viewModel.museFitReadyStreakSeconds == harness.viewModel.museFitReadyRequiredSeconds)

        harness.viewModel.startMuseRecordingFromFitCalibration()
        await waitUntil { harness.viewModel.museCanStopRecording }

        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museRecordingSummary != nil }
        #expect(harness.viewModel.museRecordingSummary?.startedWithFitOverride == false)
        #expect(harness.viewModel.museRecordingSummary?.recordingReliability == .verifiedFit)
    }

    @Test func museFitOverrideMarksLimitedReliability() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180,
                        fitGuidance: .good
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)
        #expect(harness.viewModel.museSessionFeedback.contains("low reliability warning"))

        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museRecordingSummary != nil }
        #expect(harness.viewModel.museRecordingSummary?.startedWithFitOverride == true)
        #expect(harness.viewModel.museRecordingSummary?.recordingReliability == .limitedFit)
    }

    @Test func museFitDiagnosticsPublishesPrimaryBlockerAndSensorStatuses() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                fitDiagnosticsSnapshot: { _ in
                    MuseLiveDiagnostics(
                        elapsedSeconds: 9,
                        signalConfidence: 0.35,
                        awakeLikelihood: 0.55,
                        headbandOnCoverage: 0.74,
                        qualityGateCoverage: 0.22,
                        fitGuidance: .adjustHeadband,
                        rawDataPacketCount: 220,
                        rawArtifactPacketCount: 18,
                        parsedPacketCount: 120,
                        droppedPacketCount: 100,
                        droppedDataPacketTypeCounts: [41: 82, 2: 18],
                        lastPacketAgeSeconds: 0.3,
                        fitReadiness: MuseFitReadinessSnapshot(
                            isReady: false,
                            primaryBlocker: .poorHsiPrecision,
                            blockers: [.poorHsiPrecision, .lowHeadbandCoverage, .lowQualityCoverage],
                            goodChannelCount: 2,
                            hsiGoodChannelCount: 1
                        ),
                        sensorStatuses: [
                            MuseSensorFitStatus(
                                sensor: .eeg1,
                                isGood: true,
                                hsiPrecision: 1,
                                passesIsGood: true,
                                passesHsi: true
                            ),
                            MuseSensorFitStatus(
                                sensor: .eeg2,
                                isGood: false,
                                hsiPrecision: 4,
                                passesIsGood: false,
                                passesHsi: false
                            ),
                            MuseSensorFitStatus(
                                sensor: .eeg3,
                                isGood: false,
                                hsiPrecision: 4,
                                passesIsGood: false,
                                passesHsi: false
                            ),
                            MuseSensorFitStatus(
                                sensor: .eeg4,
                                isGood: true,
                                hsiPrecision: 2,
                                passesIsGood: true,
                                passesHsi: true
                            ),
                        ],
                        droppedPacketTypes: [
                            MuseDroppedPacketTypeCount(code: 41, label: "optics", count: 82),
                            MuseDroppedPacketTypeCount(code: 2, label: "eeg", count: 18),
                        ]
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        harness.viewModel.startMuseRecording()

        await waitUntil { harness.viewModel.museFitDiagnostics != nil }
        #expect(harness.viewModel.museFitPrimaryBlockerText?.contains("HSI precision") == true)
        #expect(harness.viewModel.museFitDiagnostics?.sensorStatuses.count == 4)
    }

    @Test func museSetupDiagnosticsSnapshotUpdatesPublishedURLs() async {
        let setupURL = URL(fileURLWithPath: "/tmp/setup-diagnostics/session-1/manifest.json")
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                snapshotSetupDiagnosticsCapture: { _ in
                    [setupURL]
                }
            )
        )

        let exported = await harness.viewModel.exportMuseSetupDiagnosticsSnapshot()

        #expect(exported == [setupURL])
        #expect(harness.viewModel.museSetupDiagnosticsFileURLs == [setupURL])
    }

    @Test func museSetupDiagnosticsAvailabilityRefreshesAfterConnectFailure() async {
        let setupURL = URL(fileURLWithPath: "/tmp/setup-diagnostics/connect-failure/manifest.json")
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                connectHeadband: { _, _ in
                    throw MuseSessionServiceError.notConnected
                },
                latestSetupDiagnosticsCapture: {
                    [setupURL]
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()

        await waitUntil { harness.viewModel.museSetupDiagnosticsFileURLs == [setupURL] }
    }

    @Test func museFitCalibrationCloseCapturesSetupDiagnosticsSnapshot() async {
        let setupURL = URL(fileURLWithPath: "/tmp/setup-diagnostics/modal-close/manifest.json")
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                snapshotSetupDiagnosticsCapture: { _ in
                    [setupURL]
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        harness.viewModel.startMuseRecording()
        await waitUntil { harness.viewModel.isMuseFitCalibrationPresented }

        harness.viewModel.dismissMuseFitCalibration()
        await waitUntil { harness.viewModel.museSetupDiagnosticsFileURLs == [setupURL] }
    }

    @Test func museDiagnosticsExportRequiresStoppedSummaryWithFiles() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180,
                        awakeLikelihood: 0.7,
                        fitGuidance: .adjustHeadband,
                        diagnosticsFileURLs: [
                            URL(fileURLWithPath: "/tmp/session.muse"),
                            URL(fileURLWithPath: "/tmp/decisions.ndjson"),
                        ]
                    )
                }
            )
        )

        #expect(harness.viewModel.museRecordingSummary == nil)
        #expect(museCanExportDiagnostics(harness.viewModel) == false)

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)
        #expect(museCanExportDiagnostics(harness.viewModel) == false)

        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museRecordingSummary != nil }

        #expect(museCanExportDiagnostics(harness.viewModel) == true)
        #expect(harness.viewModel.museRecordingSummary?.diagnosticsFileURLs.count == 2)
    }

    @Test func museRecordingPublishesLiveDiagnosticsWhileRecording() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180
                    )
                },
                recordingDiagnosticsSnapshot: { _ in
                    MuseLiveDiagnostics(
                        elapsedSeconds: 20,
                        signalConfidence: 0.44,
                        awakeLikelihood: 0.63,
                        headbandOnCoverage: 0.91,
                        qualityGateCoverage: 0.67,
                        fitGuidance: .adjustHeadband,
                        rawDataPacketCount: 820,
                        rawArtifactPacketCount: 120,
                        parsedPacketCount: 710,
                        droppedPacketCount: 230,
                        droppedDataPacketTypeCounts: [41: 210, 2: 20],
                        lastPacketAgeSeconds: 0.3
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)
        await waitUntil { harness.viewModel.museLiveDiagnostics != nil }

        #expect(harness.viewModel.museLiveDiagnostics?.isReceivingData == true)
        #expect(harness.viewModel.museLiveDiagnostics?.fitGuidance == .adjustHeadband)

        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museRecordingSummary != nil }
        #expect(harness.viewModel.museLiveDiagnostics == nil)
    }

    @Test func museNightOutcomePersistenceIgnoresAwakeLikelihood() async {
        let lowAwakeOutcome = await savedMuseOutcomeForPersistence(awakeLikelihood: 0.05)
        let highAwakeOutcome = await savedMuseOutcomeForPersistence(awakeLikelihood: 0.95)

        #expect(lowAwakeOutcome == highAwakeOutcome)
        #expect(lowAwakeOutcome?.microArousalCount == 6)
        #expect(lowAwakeOutcome?.microArousalRatePerHour == 2)
        #expect(lowAwakeOutcome?.confidence == 0.8)
        #expect(lowAwakeOutcome?.source == "muse_athena_heuristic_v1")
    }

    @Test func museConnectNeedsLicenseSurfacesState() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                connectHeadband: { _, _ in
                    throw MuseSessionServiceError.needsLicense
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()

        await waitUntil { harness.viewModel.museConnectionStatusText == "Needs license" }
        #expect(harness.viewModel.museSessionFeedback.contains("license"))
    }

    @Test func museConnectUnsupportedModelSurfacesState() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                connectHeadband: { _, _ in
                    throw MuseSessionServiceError.unsupportedHeadbandModel
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()

        await waitUntil { harness.viewModel.museConnectionStatusText.contains("not supported") }
        #expect(harness.viewModel.museSessionFeedback.contains("MS-03"))
    }

    @Test func museNightOutcomeSaveFailureRevertsOutcomeRecords() async {
        let harness = AppViewModelHarness(
            initialNightOutcomes: [
                NightOutcome(
                    nightId: "2026-02-20",
                    microArousalCount: 9,
                    microArousalRatePerHour: 1.8,
                    confidence: 0.7,
                    totalSleepMinutes: 360,
                    source: "wearable",
                    createdAt: "2026-02-20T07:30:00Z"
                )
            ],
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            },
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180
                    )
                }
            )
        )

        let beforeRecords = harness.viewModel.snapshot.outcomeRecords

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)
        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museCanSaveNightOutcome }
        harness.viewModel.saveMuseNightOutcome()

        await waitUntil { harness.viewModel.museSessionFeedback.contains("Reverted.") }
        #expect(harness.viewModel.snapshot.outcomeRecords == beforeRecords)
        #expect(harness.viewModel.museCanSaveNightOutcome == true)
    }

    @Test func museRecordingStopsWhenAppMovesToBackground() async {
        let harness = AppViewModelHarness(
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-2.5 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 5,
                        confidence: 0.76,
                        totalSleepMinutes: 150
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)

        harness.viewModel.handleAppMovedToBackground()

        await waitUntil { harness.viewModel.museRecordingSummary != nil }
        #expect(harness.viewModel.museSessionFeedback.contains("background"))
        #expect(harness.viewModel.museCanSaveNightOutcome == true)
    }

    @Test func mapLensUsesExplicitEmptyStateWhenPillarHasNoMappedNodes() {
        let sleepPillar = HealthPillar(id: "sleep")
        let financialPillar = HealthPillar(id: "financialSecurity")
        let policy = planningPolicy(pillars: [
            HealthPillarDefinition(id: sleepPillar, title: "Sleep", rank: 1),
            HealthPillarDefinition(id: financialPillar, title: "Financial Security", rank: 2),
        ])
        let foundationCatalog = foundationCatalog(mappings: [
            FoundationCatalogInterventionMapping(
                interventionID: "sleep_habit",
                pillars: [sleepPillar],
                tags: [.foundation, .coreFloor],
                foundationRole: .maintenance,
                acuteTargetNodeIDs: ["SLEEP_DEP"],
                defaultMinutes: 15,
                ladderTemplateID: "sleep",
                preferredWindows: nil
            ),
        ])
        let graph = CausalGraphData(
            nodes: [
                GraphNodeElement(data: GraphNodeData(id: "SLEEP_HYG_TX", label: "Sleep Habit", styleClass: "intervention", confirmed: nil, tier: nil, tooltip: nil)),
                GraphNodeElement(data: GraphNodeData(id: "SLEEP_DEP", label: "Sleep Debt", styleClass: "moderate", confirmed: nil, tier: nil, tooltip: nil)),
            ],
            edges: [
                GraphEdgeElement(data: GraphEdgeData(source: "SLEEP_HYG_TX", target: "SLEEP_DEP", label: nil, edgeType: "forward", edgeColor: nil, tooltip: nil)),
            ]
        )
        let snapshot = snapshot(
            inputs: [
                inputStatus(id: "sleep_habit", name: "Sleep Habit", graphNodeID: "SLEEP_HYG_TX", isActive: true),
            ]
        )
        let harness = AppViewModelHarness(
            snapshot: snapshot,
            graphData: graph,
            initialFoundationCatalog: foundationCatalog,
            initialPlanningPolicy: policy
        )

        harness.viewModel.setHealthLensPreset(HealthLensPreset.pillar)
        harness.viewModel.setHealthLensPillar(financialPillar)

        #expect(harness.viewModel.projectedSituationGraphData.nodes.isEmpty)
        #expect(harness.viewModel.projectedSituationGraphData.edges.isEmpty)
        #expect(harness.viewModel.projectedSituationGraphIsLensFilteredEmpty)
        #expect(harness.viewModel.projectedSituationGraphEmptyMessage.contains("Financial Security"))
    }

    @Test func lensFilteringParitiesAcrossInputsMapAndProgressCharts() {
        let sleepPillar = HealthPillar(id: "sleep")
        let stressPillar = HealthPillar(id: "stressManagement")
        let policy = planningPolicy(pillars: [
            HealthPillarDefinition(id: sleepPillar, title: "Sleep", rank: 1),
            HealthPillarDefinition(id: stressPillar, title: "Stress", rank: 2),
        ])
        let foundationCatalog = foundationCatalog(mappings: [
            FoundationCatalogInterventionMapping(
                interventionID: "sleep_habit",
                pillars: [sleepPillar],
                tags: [.foundation, .coreFloor],
                foundationRole: .maintenance,
                acuteTargetNodeIDs: ["SLEEP_DEP"],
                defaultMinutes: 15,
                ladderTemplateID: "sleep",
                preferredWindows: nil
            ),
            FoundationCatalogInterventionMapping(
                interventionID: "stress_habit",
                pillars: [stressPillar],
                tags: [.foundation, .maintenance],
                foundationRole: .maintenance,
                acuteTargetNodeIDs: ["STRESS"],
                defaultMinutes: 15,
                ladderTemplateID: "stress",
                preferredWindows: nil
            ),
        ])
        let graph = CausalGraphData(
            nodes: [
                GraphNodeElement(data: GraphNodeData(id: "SLEEP_HYG_TX", label: "Sleep Habit", styleClass: "intervention", confirmed: nil, tier: nil, tooltip: nil)),
                GraphNodeElement(data: GraphNodeData(id: "SLEEP_DEP", label: "Sleep Debt", styleClass: "moderate", confirmed: nil, tier: nil, tooltip: nil)),
                GraphNodeElement(data: GraphNodeData(id: "MINDFULNESS_TX", label: "Stress Habit", styleClass: "intervention", confirmed: nil, tier: nil, tooltip: nil)),
                GraphNodeElement(data: GraphNodeData(id: "STRESS", label: "Stress", styleClass: "moderate", confirmed: nil, tier: nil, tooltip: nil)),
            ],
            edges: [
                GraphEdgeElement(data: GraphEdgeData(source: "SLEEP_HYG_TX", target: "SLEEP_DEP", label: nil, edgeType: "forward", edgeColor: nil, tooltip: nil)),
                GraphEdgeElement(data: GraphEdgeData(source: "MINDFULNESS_TX", target: "STRESS", label: nil, edgeType: "forward", edgeColor: nil, tooltip: nil)),
            ]
        )
        let snapshot = snapshot(
            inputs: [
                inputStatus(id: "sleep_habit", name: "Sleep Habit", graphNodeID: "SLEEP_HYG_TX", isActive: true),
                inputStatus(id: "stress_habit", name: "Stress Habit", graphNodeID: "MINDFULNESS_TX", isActive: true),
            ]
        )
        let morningStates = [
            MorningState(
                nightId: "2026-02-21",
                globalSensation: 7,
                neckTightness: 6,
                jawSoreness: 5,
                earFullness: 4,
                healthAnxiety: 3,
                stressLevel: 8,
                createdAt: "2026-02-21T08:00:00Z",
                graphAssociation: GraphAssociationRef(
                    graphVersion: "graph-v1",
                    nodeIDs: ["SLEEP_HYG_TX"],
                    edgeIDs: []
                )
            ),
            MorningState(
                nightId: "2026-02-20",
                globalSensation: 6,
                neckTightness: 4,
                jawSoreness: 4,
                earFullness: 3,
                healthAnxiety: 3,
                stressLevel: 7,
                createdAt: "2026-02-20T08:00:00Z",
                graphAssociation: GraphAssociationRef(
                    graphVersion: "graph-v1",
                    nodeIDs: ["MINDFULNESS_TX"],
                    edgeIDs: []
                )
            ),
            MorningState(
                nightId: "2026-02-19",
                globalSensation: 5,
                neckTightness: 3,
                jawSoreness: 3,
                earFullness: 2,
                healthAnxiety: 2,
                stressLevel: 4,
                createdAt: "2026-02-19T08:00:00Z",
                graphAssociation: nil
            ),
        ]
        let harness = AppViewModelHarness(
            snapshot: snapshot,
            graphData: graph,
            initialMorningStates: morningStates,
            initialFoundationCatalog: foundationCatalog,
            initialPlanningPolicy: policy
        )

        harness.viewModel.setHealthLensPreset(HealthLensPreset.pillar)
        harness.viewModel.setHealthLensPillar(sleepPillar)

        let projectedInputIDs = Set(harness.viewModel.projectedInputs.map { $0.id })
        #expect(projectedInputIDs == Set(["sleep_habit"]))
        #expect(harness.viewModel.projectedSituationGraphData.nodes.contains { $0.data.id == "SLEEP_DEP" })
        #expect(harness.viewModel.projectedProgressMorningStatesForCharts.count == 1)
        #expect(harness.viewModel.projectedProgressMorningStatesForCharts.first?.nightId == "2026-02-21")
        let exclusionNote = harness.viewModel.projectedProgressExcludedChartsNote
        #expect(exclusionNote?.contains("unscoped") == true)
        #expect(exclusionNote?.contains("outside lens") == true)
    }

    @Test func higherRungCompletionPersistsOverrideAtAchievedRung() async {
        let patchRecorder = PatchRecorder()
        let sleepPillar = HealthPillar(id: "sleep")
        let foundationCatalog = foundationCatalog(mappings: [
            FoundationCatalogInterventionMapping(
                interventionID: "sleep_habit",
                pillars: [sleepPillar],
                tags: [.foundation, .coreFloor],
                foundationRole: .maintenance,
                acuteTargetNodeIDs: ["SLEEP_DEP"],
                defaultMinutes: 30,
                ladderTemplateID: "sleep",
                preferredWindows: nil
            ),
        ])
        let policy = planningPolicy(pillars: [
            HealthPillarDefinition(id: sleepPillar, title: "Sleep", rank: 1),
        ])
        let snapshot = snapshot(
            inputs: [
                inputStatus(id: "sleep_habit", name: "Sleep Habit", graphNodeID: "SLEEP_HYG_TX", isActive: true),
            ]
        )
        let plannerState = HabitPlannerState(
            entriesByInterventionID: [
                "sleep_habit": HabitPlannerEntryState(
                    currentRungIndex: 2,
                    consecutiveCompletions: 0,
                    lastCompletedDayKey: nil,
                    lastSuggestedDayKey: nil,
                    learnedDurationMinutes: nil
                ),
            ],
            updatedAt: "2026-02-20T08:00:00Z"
        )
        let harness = AppViewModelHarness(
            snapshot: snapshot,
            initialHabitPlannerState: plannerState,
            initialFoundationCatalog: foundationCatalog,
            initialPlanningPolicy: policy,
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        harness.viewModel.toggleInputCheckedToday("sleep_habit")
        await waitUntil { await patchRecorder.count() >= 1 }
        harness.viewModel.recordHigherRungCompletion(
            interventionID: "sleep_habit",
            achievedRungID: "full"
        )
        await waitUntil { await patchRecorder.count() >= 2 }

        let rungStatus = harness.viewModel.projectedHabitRungStatusByInterventionID["sleep_habit"]
        #expect(rungStatus?.currentRungID == "full")
        #expect(rungStatus?.targetRungID == "full")

        let patch = await patchRecorder.lastPatch()
        let entry = patch?.habitPlannerState?.entriesByInterventionID["sleep_habit"]
        #expect(entry?.currentRungIndex == 0)
    }

    @Test func guideSectionedExportAndImportRevertsAtomicallyOnPersistFailure() async throws {
        let initialGraph = CausalGraphData(
            nodes: [
                GraphNodeElement(data: GraphNodeData(id: "A", label: "A", styleClass: "mechanism", confirmed: nil, tier: nil, tooltip: nil)),
            ],
            edges: []
        )
        let initialPlannerPreferences = PlannerPreferencesState(
            defaultAvailableMinutes: 90,
            modeOverride: .baseline,
            flareSensitivity: .balanced,
            updatedAt: "2026-02-21T00:00:00Z",
            dailyTimeBudgetState: DailyTimeBudgetState.from(
                availableMinutes: 90,
                updatedAt: "2026-02-21T00:00:00Z"
            )
        )
        let harness = AppViewModelHarness(
            graphData: initialGraph,
            initialPlannerPreferencesState: initialPlannerPreferences,
            persistUserDataPatch: { _ in
                throw PatchFailure.writeFailed
            }
        )

        harness.viewModel.exportGuideSections([.planner])
        await waitUntil { harness.viewModel.projectedGuideExportEnvelopeText != nil }
        let exportText = try #require(harness.viewModel.projectedGuideExportEnvelopeText)
        let codec = GraphPatchJSONCodec()
        let exportEnvelope = try codec.decodeGuideExportEnvelope(from: exportText)
        #expect(exportEnvelope.sections == [.planner])
        #expect(exportEnvelope.graph == nil)
        #expect(exportEnvelope.aliases == nil)
        #expect(exportEnvelope.planner != nil)

        let updatedGraph = CausalGraphData(
            nodes: [
                GraphNodeElement(data: GraphNodeData(id: "A", label: "A", styleClass: "mechanism", confirmed: nil, tier: nil, tooltip: nil)),
                GraphNodeElement(data: GraphNodeData(id: "B", label: "B", styleClass: "mechanism", confirmed: nil, tier: nil, tooltip: nil)),
            ],
            edges: []
        )
        let importEnvelope = GuideExportEnvelope(
            schemaVersion: "guide-transfer.v1",
            sections: [.graph, .planner],
            graph: GuideGraphTransferPayload(
                graphVersion: "graph-v2",
                baseGraphVersion: "graph-v1",
                lastModified: "2026-02-21T01:00:00Z",
                graphData: updatedGraph
            ),
            aliases: nil,
            planner: GuidePlannerTransferPayload(
                plannerPreferencesState: PlannerPreferencesState(
                    defaultAvailableMinutes: 45,
                    modeOverride: .flare,
                    flareSensitivity: .balanced,
                    updatedAt: "2026-02-21T01:00:00Z",
                    dailyTimeBudgetState: DailyTimeBudgetState.from(
                        availableMinutes: 45,
                        updatedAt: "2026-02-21T01:00:00Z"
                    )
                ),
                habitPlannerState: .empty,
                healthLensState: HealthLensState(
                    preset: .acute,
                    selectedPillar: nil,
                    updatedAt: "2026-02-21T01:00:00Z"
                )
            )
        )
        let importText = try codec.encodeGuideExportEnvelope(importEnvelope)
        harness.viewModel.previewGuideImportPayload(importText)
        #expect(harness.viewModel.projectedGuideImportPreview?.isValid == true)
        harness.viewModel.applyPendingGuideImportPayload()
        await waitUntil { harness.viewModel.exploreFeedback.contains("failed and was reverted") }

        #expect(harness.viewModel.graphData == initialGraph)
        #expect(harness.viewModel.projectedPlannerTimeBudgetState.availableMinutes == 90)
        #expect(harness.viewModel.projectedHealthLensPreset == .all)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func startMuseRecordingWithFitOverride(_ viewModel: AppViewModel) async {
        viewModel.startMuseRecording()
        await waitUntil { viewModel.isMuseFitCalibrationPresented }
        viewModel.startMuseRecordingWithFitOverride()
        await waitUntil { viewModel.museCanStopRecording }
    }

    private func museCanExportDiagnostics(_ viewModel: AppViewModel) -> Bool {
        guard let summary = viewModel.museRecordingSummary else {
            return false
        }

        return !summary.diagnosticsFileURLs.isEmpty
    }

    private func savedMuseOutcomeForPersistence(awakeLikelihood: Double) async -> NightOutcome? {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            },
            museSessionService: MockMuseSessionService(
                stopSession: { endDate in
                    MuseRecordingSummary(
                        startedAt: endDate.addingTimeInterval(-3 * 60 * 60),
                        endedAt: endDate,
                        microArousalCount: 6,
                        confidence: 0.8,
                        totalSleepMinutes: 180,
                        awakeLikelihood: awakeLikelihood,
                        fitGuidance: .adjustHeadband,
                        diagnosticsFileURLs: [
                            URL(fileURLWithPath: "/tmp/session.muse"),
                            URL(fileURLWithPath: "/tmp/decisions.ndjson"),
                        ]
                    )
                }
            )
        )

        harness.viewModel.scanForMuseHeadband()
        await waitUntil { harness.viewModel.museCanConnect }
        harness.viewModel.connectToMuseHeadband()
        await waitUntil { harness.viewModel.museCanStartRecording }
        await startMuseRecordingWithFitOverride(harness.viewModel)
        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museCanSaveNightOutcome }
        harness.viewModel.saveMuseNightOutcome()
        await waitUntil { await patchRecorder.count() == 1 }

        let patch = await patchRecorder.lastPatch()
        return patch?.nightOutcomes?.first(where: { $0.nightId == "2026-02-21" })
    }

    private func planningPolicy(pillars: [HealthPillarDefinition]) -> PlanningPolicy {
        PlanningPolicy(
            policyID: "planner.v1.test",
            pillars: pillars,
            coreFloorPillars: pillars.prefix(2).map(\.id),
            highPriorityPillarCutoff: max(1, min(5, pillars.count)),
            defaultAvailableMinutes: 90,
            flareEnterThreshold: 0.65,
            flareExitThreshold: 0.45,
            flareLookbackDays: 3,
            flareEnterRequiredDays: 2,
            flareExitStableDays: 3,
            ladder: .default
        )
    }

    private func foundationCatalog(
        mappings: [FoundationCatalogInterventionMapping]
    ) -> FoundationCatalog {
        FoundationCatalog(
            schemaVersion: "foundation.v1",
            sourceReportPath: "/tmp/test.md",
            generatedAt: "2026-02-21T00:00:00Z",
            pillars: [],
            interventionMappings: mappings
        )
    }

    private func snapshot(inputs: [InputStatus]) -> DashboardSnapshot {
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
                focusedNode: "None",
                tier: "Tier 0",
                visibleHotspots: 0,
                topSource: "None"
            ),
            inputs: inputs
        )
    }

    private func inputStatus(
        id: String,
        name: String,
        graphNodeID: String,
        isActive: Bool
    ) -> InputStatus {
        InputStatus(
            id: id,
            name: name,
            trackingMode: .binary,
            statusText: "pending",
            completion: 0,
            isCheckedToday: false,
            doseState: nil,
            completionEvents: [],
            graphNodeID: graphNodeID,
            classificationText: nil,
            isActive: isActive,
            evidenceLevel: nil,
            evidenceSummary: nil,
            detailedDescription: nil,
            citationIDs: [],
            externalLink: nil,
            appleHealthState: nil
        )
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
        graphData: CausalGraphData = CanonicalGraphLoader.loadGraphOrFallback(),
        initialExperienceFlow: ExperienceFlow = .empty,
        initialDailyCheckIns: [String: [String]] = [:],
        initialDailyDoseProgress: [String: [String: Double]] = [:],
        initialInterventionCompletionEvents: [InterventionCompletionEvent] = [],
        initialInterventionDoseSettings: [String: DoseSettings] = [:],
        initialAppleHealthConnections: [String: AppleHealthConnection] = [:],
        initialNightOutcomes: [NightOutcome] = [],
        initialMorningStates: [MorningState] = [],
        initialMorningQuestionnaire: MorningQuestionnaire? = nil,
        initialPlannerPreferencesState: PlannerPreferencesState? = nil,
        initialHabitPlannerState: HabitPlannerState? = nil,
        initialHealthLensState: HealthLensState? = nil,
        initialActiveInterventions: [String] = [],
        initialInterventionsCatalog: InterventionsCatalog = .empty,
        initialFoundationCatalog: FoundationCatalog? = nil,
        initialPlanningPolicy: PlanningPolicy? = nil,
        planningMetadataResolver: HabitPlanningMetadataResolver? = nil,
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true },
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        museSessionService: MuseSessionService = MockMuseSessionService(),
        museLicenseData: Data? = nil,
        museDiagnosticsPollingIntervalNanoseconds: UInt64 = 5_000_000
    ) {
        let recorder = AnnouncementRecorder()
        let announcer = AccessibilityAnnouncer { message in
            recorder.messages.append(message)
        }
        self.recorder = recorder
        viewModel = AppViewModel(
            snapshot: snapshot,
            graphData: graphData,
            initialExperienceFlow: initialExperienceFlow,
            initialDailyCheckIns: initialDailyCheckIns,
            initialDailyDoseProgress: initialDailyDoseProgress,
            initialInterventionCompletionEvents: initialInterventionCompletionEvents,
            initialInterventionDoseSettings: initialInterventionDoseSettings,
            initialAppleHealthConnections: initialAppleHealthConnections,
            initialNightOutcomes: initialNightOutcomes,
            initialMorningStates: initialMorningStates,
            initialMorningQuestionnaire: initialMorningQuestionnaire,
            initialPlannerPreferencesState: initialPlannerPreferencesState,
            initialHabitPlannerState: initialHabitPlannerState,
            initialHealthLensState: initialHealthLensState,
            initialActiveInterventions: initialActiveInterventions,
            initialInterventionsCatalog: initialInterventionsCatalog,
            initialFoundationCatalog: initialFoundationCatalog,
            initialPlanningPolicy: initialPlanningPolicy,
            persistUserDataPatch: persistUserDataPatch,
            appleHealthDoseService: appleHealthDoseService,
            museSessionService: museSessionService,
            museLicenseData: museLicenseData,
            nowProvider: {
                let calendar = Calendar(identifier: .gregorian)
                return calendar.date(from: DateComponents(year: 2026, month: 2, day: 21)) ?? Date()
            },
            museDiagnosticsPollingIntervalNanoseconds: museDiagnosticsPollingIntervalNanoseconds,
            planningMetadataResolver: planningMetadataResolver,
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
