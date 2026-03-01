import SwiftUI

struct ExploreTabShell: View {
    @Bindable var viewModel: AppViewModel
    let selectedSkinID: TelocareSkinID
    let isMuseSessionEnabled: Bool

    @State private var visitedTabs: Set<ExploreTab> = [.inputs]

    var body: some View {
        TabView(selection: selectedTabBinding) {
            lazyTab(tab: .inputs, accessibilityID: AccessibilityID.exploreInputsScreen) {
                ExploreInputsScreen(
                    inputs: viewModel.projectedInputs,
                    graphData: viewModel.graphData,
                    onToggleCheckedToday: viewModel.toggleInputCheckedToday,
                    onIncrementDose: viewModel.incrementInputDose,
                    onDecrementDose: viewModel.decrementInputDose,
                    onResetDose: viewModel.resetInputDose,
                    onUpdateDoseSettings: viewModel.updateDoseSettings,
                    onConnectAppleHealth: viewModel.connectInputToAppleHealth,
                    onDisconnectAppleHealth: viewModel.disconnectInputFromAppleHealth,
                    onRefreshAppleHealth: { inputID in
                        await viewModel.refreshAppleHealth(for: inputID, trigger: .manual)
                    },
                    onRefreshAllAppleHealth: {
                        await viewModel.refreshAllConnectedAppleHealth(trigger: .manual)
                    },
                    onToggleActive: viewModel.toggleInputActive,
                    planningMetadataByInterventionID: viewModel.projectedPlanningMetadataByInterventionID,
                    pillarAssignments: viewModel.projectedPillarAssignments,
                    orderedPillars: viewModel.projectedHealthLensPillars,
                    habitRungStatusByInterventionID: viewModel.projectedHabitRungStatusByInterventionID,
                    plannedInterventionIDs: viewModel.projectedPlannedInterventionIDs,
                    onRecordHigherRungCompletion: { interventionID, rungID in
                        viewModel.recordHigherRungCompletion(
                            interventionID: interventionID,
                            achievedRungID: rungID
                        )
                    },
                    selectedSkinID: selectedSkinID
                )
            }

            lazyTab(tab: .situation, accessibilityID: AccessibilityID.exploreSituationScreen) {
                ExploreSituationScreen(
                    situation: viewModel.snapshot.situation,
                    graphData: viewModel.projectedSituationGraphData,
                    graphVersionHint: viewModel.projectedGuideGraphVersion,
                    displayFlags: viewModel.graphDisplayFlags,
                    focusedNodeID: viewModel.focusedNodeID,
                    graphSelectionText: viewModel.graphSelectionText,
                    inputs: viewModel.projectedInputs,
                    planningMetadataByInterventionID: viewModel.projectedPlanningMetadataByInterventionID,
                    orderedPillars: viewModel.projectedHealthLensPillars,
                    pillarAssignments: viewModel.projectedPillarAssignments,
                    selectedLensMode: viewModel.projectedHealthLensMode,
                    selectedLensPillars: viewModel.projectedSelectedHealthLensPillars,
                    selectedLensIsAllSelected: viewModel.projectedHealthLensSelection.isAllSelected,
                    onGraphEvent: viewModel.handleGraphEvent,
                    onAction: viewModel.performExploreAction,
                    onShowInterventionsChanged: viewModel.setShowInterventionNodes,
                    onShowFeedbackEdgesChanged: viewModel.setShowFeedbackEdges,
                    onShowProtectiveEdgesChanged: viewModel.setShowProtectiveEdges,
                    onToggleNodeDeactivated: viewModel.toggleGraphNodeDeactivated,
                    onToggleNodeExpanded: { nodeID in
                        _ = viewModel.toggleGraphNodeExpanded(nodeID)
                    },
                    onToggleEdgeDeactivated: { sourceID, targetID, label, edgeType in
                        viewModel.toggleGraphEdgeDeactivated(
                            sourceID: sourceID,
                            targetID: targetID,
                            label: label,
                            edgeType: edgeType
                        )
                    },
                    isLensFilteredEmpty: viewModel.projectedSituationGraphIsLensFilteredEmpty,
                    emptyLensMessage: viewModel.projectedSituationGraphEmptyMessage,
                    onClearLensFilter: viewModel.selectAllHealthLensPillars,
                    selectedSkinID: selectedSkinID
                )
            }

            lazyTab(tab: .outcomes, accessibilityID: AccessibilityID.exploreOutcomesScreen) {
                ExploreOutcomesScreen(
                    outcomes: viewModel.snapshot.outcomes,
                    outcomeRecords: viewModel.snapshot.outcomeRecords,
                    outcomesMetadata: viewModel.snapshot.outcomesMetadata,
                    morningStates: viewModel.morningStateHistory,
                    chartMorningStates: viewModel.projectedProgressMorningStatesForCharts,
                    chartNightOutcomes: viewModel.projectedProgressNightOutcomesForCharts,
                    chartExclusionNote: viewModel.projectedProgressExcludedChartsNote,
                    morningOutcomeSelection: viewModel.morningOutcomeSelection,
                    morningCheckInFields: viewModel.morningCheckInFields,
                    requiredMorningCheckInFields: viewModel.requiredMorningCheckInFields,
                    foundationCheckInNightID: viewModel.foundationCheckInNightID,
                    foundationQuestions: viewModel.foundationCheckInQuestions,
                    foundationResponsesByQuestionID: viewModel.foundationCheckInResponsesByQuestionID,
                    foundationRequiredQuestionIDs: viewModel.foundationRequiredQuestionIDs,
                    morningTrendMetrics: viewModel.morningTrendMetricOptions,
                    museConnectionStatusText: viewModel.museConnectionStatusText,
                    museRecordingStatusText: viewModel.museRecordingStatusText,
                    museSessionFeedback: viewModel.museSessionFeedback,
                    museDisclaimerText: viewModel.museDisclaimerText,
                    museCanScan: viewModel.museCanScan,
                    museCanConnect: viewModel.museCanConnect,
                    museCanDisconnect: viewModel.museCanDisconnect,
                    museCanStartRecording: viewModel.museCanStartRecording,
                    museCanStopRecording: viewModel.museCanStopRecording,
                    museIsRecording: viewModel.museIsRecording,
                    museCanSaveNightOutcome: viewModel.museCanSaveNightOutcome,
                    museRecordingSummary: viewModel.museRecordingSummary,
                    museLiveDiagnostics: viewModel.museLiveDiagnostics,
                    museSetupDiagnosticsFileURLs: viewModel.museSetupDiagnosticsFileURLs,
                    isMuseFitCalibrationPresented: viewModel.isMuseFitCalibrationPresented,
                    museFitDiagnostics: viewModel.museFitDiagnostics,
                    museFitPrimaryBlockerText: viewModel.museFitPrimaryBlockerText,
                    museFitReadyStreakSeconds: viewModel.museFitReadyStreakSeconds,
                    museFitReadyRequiredSeconds: viewModel.museFitReadyRequiredSeconds,
                    museCanStartRecordingFromFitCalibration: viewModel.museCanStartRecordingFromFitCalibration,
                    museCanStartRecordingWithFitOverride: viewModel.museCanStartRecordingWithFitOverride,
                    onSetMorningOutcomeValue: viewModel.setMorningOutcomeValue,
                    onSetFoundationCheckInValue: viewModel.setFoundationCheckInValue,
                    onScanForMuse: viewModel.scanForMuseHeadband,
                    onConnectToMuse: viewModel.connectToMuseHeadband,
                    onDisconnectMuse: viewModel.disconnectMuseHeadband,
                    onStartMuseRecording: viewModel.startMuseRecording,
                    onDismissMuseFitCalibration: viewModel.dismissMuseFitCalibration,
                    onStartMuseRecordingFromFitCalibration: viewModel.startMuseRecordingFromFitCalibration,
                    onStartMuseRecordingWithFitOverride: viewModel.startMuseRecordingWithFitOverride,
                    onExportMuseSetupDiagnosticsSnapshot: {
                        await viewModel.exportMuseSetupDiagnosticsSnapshot()
                    },
                    onStopMuseRecording: viewModel.stopMuseRecording,
                    onSaveMuseNightOutcome: viewModel.saveMuseNightOutcome,
                    isMuseSessionEnabled: isMuseSessionEnabled,
                    flareSuggestion: viewModel.projectedFlareSuggestion,
                    onAcceptFlareSuggestion: viewModel.acceptFlareSuggestion,
                    onDismissFlareSuggestion: viewModel.dismissFlareSuggestion,
                    selectedSkinID: selectedSkinID
                )
            }

            lazyTab(tab: .chat, accessibilityID: AccessibilityID.exploreChatScreen) {
                ExploreChatScreen(
                    draft: $viewModel.chatDraft,
                    feedback: viewModel.exploreFeedback,
                    pendingGraphPatchPreview: viewModel.pendingGraphPatchPreview,
                    pendingGraphPatchConflicts: viewModel.pendingGraphPatchConflicts,
                    pendingGraphPatchConflictResolutions: viewModel.pendingGraphPatchConflictResolutions,
                    checkpointSummaries: viewModel.projectedGraphCheckpointSummaries,
                    graphVersion: viewModel.projectedGuideGraphVersion,
                    guideExportEnvelopeText: viewModel.projectedGuideExportEnvelopeText,
                    pendingGuideImportPreview: viewModel.projectedGuideImportPreview,
                    onSetConflictResolution: { operationIndex, choice in
                        viewModel.setPendingGraphPatchConflictResolution(
                            operationIndex: operationIndex,
                            choice: choice
                        )
                    },
                    onExportGuideSections: viewModel.exportGuideSections,
                    onPreviewGuideImportPayload: viewModel.previewGuideImportPayload,
                    onApplyPendingGuideImport: viewModel.applyPendingGuideImportPayload,
                    onDismissPendingGuideImport: viewModel.clearPendingGuideImportPreview,
                    onApplyPendingPatch: viewModel.applyPendingGraphPatchFromReview,
                    onDismissPendingPatch: viewModel.clearPendingGraphPatchPreview,
                    onRollbackGraphVersion: viewModel.rollbackGraph(to:),
                    onSend: viewModel.submitChatPrompt,
                    selectedSkinID: selectedSkinID
                )
            }
        }
        .onAppear {
            visitedTabs.insert(viewModel.selectedExploreTab)
        }
        .onChange(of: viewModel.selectedExploreTab) { _, tab in
            visitedTabs.insert(tab)
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
        .alert(
            "Progress Questions Updated",
            isPresented: progressQuestionProposalPresentationBinding,
            actions: {
                Button("Accept") {
                    viewModel.acceptProgressQuestionProposal()
                }
                Button("Decline", role: .cancel) {
                    viewModel.declineProgressQuestionProposal()
                }
            },
            message: {
                if let proposal = viewModel.progressQuestionProposal {
                    Text(
                        "Graph \(proposal.sourceGraphVersion) proposes \(proposal.questions.count) updated questions. Accept to adopt this set for Progress."
                    )
                } else {
                    Text("This graph version has a new question set proposal.")
                }
            }
        )
    }

    @ViewBuilder
    private func lazyTab<Content: View>(
        tab: ExploreTab,
        accessibilityID: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if visitedTabs.contains(tab) || viewModel.selectedExploreTab == tab {
                content()
            } else {
                Color.clear
            }
        }
        .tabItem { Label(tab.title, systemImage: tab.symbolName) }
        .tag(tab)
        .accessibilityIdentifier(accessibilityID)
    }

    private var selectedTabBinding: Binding<ExploreTab> {
        Binding(
            get: { viewModel.selectedExploreTab },
            set: viewModel.selectExploreTab
        )
    }

    private var progressQuestionProposalPresentationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isProgressQuestionProposalPresented },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissProgressQuestionProposalPrompt()
                }
            }
        )
    }
}
