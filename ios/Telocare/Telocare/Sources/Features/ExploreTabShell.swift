import SwiftUI

struct ExploreTabShell: View {
    @ObservedObject var viewModel: AppViewModel
    let selectedSkinID: TelocareSkinID
    let isMuseSessionEnabled: Bool

    var body: some View {
        TabView(selection: selectedTabBinding) {
            ExploreInputsScreen(
                inputs: viewModel.snapshot.inputs,
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
                selectedSkinID: selectedSkinID
            )
                .tabItem { Label(ExploreTab.inputs.title, systemImage: ExploreTab.inputs.symbolName) }
                .tag(ExploreTab.inputs)
                .accessibilityIdentifier(AccessibilityID.exploreInputsScreen)

            ExploreSituationScreen(
                situation: viewModel.snapshot.situation,
                graphData: viewModel.graphData,
                displayFlags: viewModel.graphDisplayFlags,
                focusedNodeID: viewModel.focusedNodeID,
                graphSelectionText: viewModel.graphSelectionText,
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
                selectedSkinID: selectedSkinID
            )
            .tabItem { Label(ExploreTab.situation.title, systemImage: ExploreTab.situation.symbolName) }
            .tag(ExploreTab.situation)
            .accessibilityIdentifier(AccessibilityID.exploreSituationScreen)

            ExploreOutcomesScreen(
                outcomes: viewModel.snapshot.outcomes,
                outcomeRecords: viewModel.snapshot.outcomeRecords,
                outcomesMetadata: viewModel.snapshot.outcomesMetadata,
                morningStates: viewModel.morningStateHistory,
                morningOutcomeSelection: viewModel.morningOutcomeSelection,
                morningCheckInFields: viewModel.morningCheckInFields,
                requiredMorningCheckInFields: viewModel.requiredMorningCheckInFields,
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
                selectedSkinID: selectedSkinID
            )
                .tabItem { Label(ExploreTab.outcomes.title, systemImage: ExploreTab.outcomes.symbolName) }
                .tag(ExploreTab.outcomes)
                .accessibilityIdentifier(AccessibilityID.exploreOutcomesScreen)

            ExploreChatScreen(
                draft: $viewModel.chatDraft,
                feedback: viewModel.exploreFeedback,
                onSend: viewModel.submitChatPrompt,
                selectedSkinID: selectedSkinID
            )
                .tabItem { Label(ExploreTab.chat.title, systemImage: ExploreTab.chat.symbolName) }
                .tag(ExploreTab.chat)
                .accessibilityIdentifier(AccessibilityID.exploreChatScreen)
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
    }

    private var selectedTabBinding: Binding<ExploreTab> {
        Binding(
            get: { viewModel.selectedExploreTab },
            set: viewModel.selectExploreTab
        )
    }
}
