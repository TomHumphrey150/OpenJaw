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

    @Test func graphNodeDeactivationTogglePersistsCustomDiagramPatch() async {
        let patchRecorder = PatchRecorder()
        let harness = AppViewModelHarness(
            persistUserDataPatch: { patch in
                await patchRecorder.record(patch)
                return true
            }
        )

        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated == nil)

        harness.viewModel.toggleGraphNodeDeactivated("RMMA")

        await waitUntil { await patchRecorder.count() == 1 }
        let patch = await patchRecorder.lastPatch()
        #expect(harness.viewModel.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated == true)
        #expect(
            patch?.customCausalDiagram?.graphData.nodes.first(where: { $0.data.id == "RMMA" })?.data.isDeactivated == true
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

        harness.viewModel.startMuseRecording()
        await waitUntil { harness.viewModel.museCanStopRecording }

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
        harness.viewModel.startMuseRecording()
        await waitUntil { harness.viewModel.museCanStopRecording }
        harness.viewModel.stopMuseRecording()
        await waitUntil { harness.viewModel.museRecordingSummary != nil }

        #expect(harness.viewModel.museCanSaveNightOutcome == false)
        harness.viewModel.saveMuseNightOutcome()

        await waitUntil { harness.viewModel.museSessionFeedback.contains("2 hours") }
        #expect(await patchRecorder.count() == 0)
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
        harness.viewModel.startMuseRecording()
        await waitUntil { harness.viewModel.museCanStopRecording }
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
        harness.viewModel.startMuseRecording()
        await waitUntil { harness.viewModel.museCanStopRecording }

        harness.viewModel.handleAppMovedToBackground()

        await waitUntil { harness.viewModel.museRecordingSummary != nil }
        #expect(harness.viewModel.museSessionFeedback.contains("background"))
        #expect(harness.viewModel.museCanSaveNightOutcome == true)
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
        initialInterventionCompletionEvents: [InterventionCompletionEvent] = [],
        initialInterventionDoseSettings: [String: DoseSettings] = [:],
        initialAppleHealthConnections: [String: AppleHealthConnection] = [:],
        initialNightOutcomes: [NightOutcome] = [],
        initialMorningStates: [MorningState] = [],
        initialActiveInterventions: [String] = [],
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true },
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        museSessionService: MuseSessionService = MockMuseSessionService(),
        museLicenseData: Data? = nil
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
            initialInterventionCompletionEvents: initialInterventionCompletionEvents,
            initialInterventionDoseSettings: initialInterventionDoseSettings,
            initialAppleHealthConnections: initialAppleHealthConnections,
            initialNightOutcomes: initialNightOutcomes,
            initialMorningStates: initialMorningStates,
            initialActiveInterventions: initialActiveInterventions,
            persistUserDataPatch: persistUserDataPatch,
            appleHealthDoseService: appleHealthDoseService,
            museSessionService: museSessionService,
            museLicenseData: museLicenseData,
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
