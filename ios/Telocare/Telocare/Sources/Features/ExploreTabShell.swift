import Charts
import SwiftUI

struct ExploreTabShell: View {
    @ObservedObject var viewModel: AppViewModel
    let selectedSkinID: TelocareSkinID

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
                museConnectionStatusText: viewModel.museConnectionStatusText,
                museRecordingStatusText: viewModel.museRecordingStatusText,
                museSessionFeedback: viewModel.museSessionFeedback,
                museDisclaimerText: viewModel.museDisclaimerText,
                museCanScan: viewModel.museCanScan,
                museCanConnect: viewModel.museCanConnect,
                museCanDisconnect: viewModel.museCanDisconnect,
                museCanStartRecording: viewModel.museCanStartRecording,
                museCanStopRecording: viewModel.museCanStopRecording,
                museCanSaveNightOutcome: viewModel.museCanSaveNightOutcome,
                museRecordingSummary: viewModel.museRecordingSummary,
                onSetMorningOutcomeValue: viewModel.setMorningOutcomeValue,
                onScanForMuse: viewModel.scanForMuseHeadband,
                onConnectToMuse: viewModel.connectToMuseHeadband,
                onDisconnectMuse: viewModel.disconnectMuseHeadband,
                onStartMuseRecording: viewModel.startMuseRecording,
                onStopMuseRecording: viewModel.stopMuseRecording,
                onSaveMuseNightOutcome: viewModel.saveMuseNightOutcome,
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

private struct ExploreOutcomesScreen: View {
    let outcomes: OutcomeSummary
    let outcomeRecords: [OutcomeRecord]
    let outcomesMetadata: OutcomesMetadata
    let morningStates: [MorningState]
    let morningOutcomeSelection: MorningOutcomeSelection
    let museConnectionStatusText: String
    let museRecordingStatusText: String
    let museSessionFeedback: String
    let museDisclaimerText: String
    let museCanScan: Bool
    let museCanConnect: Bool
    let museCanDisconnect: Bool
    let museCanStartRecording: Bool
    let museCanStopRecording: Bool
    let museCanSaveNightOutcome: Bool
    let museRecordingSummary: MuseRecordingSummary?
    let onSetMorningOutcomeValue: (Int?, MorningOutcomeField) -> Void
    let onScanForMuse: () -> Void
    let onConnectToMuse: () -> Void
    let onDisconnectMuse: () -> Void
    let onStartMuseRecording: () -> Void
    let onStopMuseRecording: () -> Void
    let onSaveMuseNightOutcome: () -> Void
    let selectedSkinID: TelocareSkinID

    @State private var navigationPath = NavigationPath()
    @State private var isMorningCheckInExpanded: Bool
    @State private var selectedMorningMetric: MorningTrendMetric
    @State private var selectedNightMetric: NightTrendMetric

    init(
        outcomes: OutcomeSummary,
        outcomeRecords: [OutcomeRecord],
        outcomesMetadata: OutcomesMetadata,
        morningStates: [MorningState],
        morningOutcomeSelection: MorningOutcomeSelection,
        museConnectionStatusText: String,
        museRecordingStatusText: String,
        museSessionFeedback: String,
        museDisclaimerText: String,
        museCanScan: Bool,
        museCanConnect: Bool,
        museCanDisconnect: Bool,
        museCanStartRecording: Bool,
        museCanStopRecording: Bool,
        museCanSaveNightOutcome: Bool,
        museRecordingSummary: MuseRecordingSummary?,
        onSetMorningOutcomeValue: @escaping (Int?, MorningOutcomeField) -> Void,
        onScanForMuse: @escaping () -> Void,
        onConnectToMuse: @escaping () -> Void,
        onDisconnectMuse: @escaping () -> Void,
        onStartMuseRecording: @escaping () -> Void,
        onStopMuseRecording: @escaping () -> Void,
        onSaveMuseNightOutcome: @escaping () -> Void,
        selectedSkinID: TelocareSkinID
    ) {
        self.outcomes = outcomes
        self.outcomeRecords = outcomeRecords
        self.outcomesMetadata = outcomesMetadata
        self.morningStates = morningStates
        self.morningOutcomeSelection = morningOutcomeSelection
        self.museConnectionStatusText = museConnectionStatusText
        self.museRecordingStatusText = museRecordingStatusText
        self.museSessionFeedback = museSessionFeedback
        self.museDisclaimerText = museDisclaimerText
        self.museCanScan = museCanScan
        self.museCanConnect = museCanConnect
        self.museCanDisconnect = museCanDisconnect
        self.museCanStartRecording = museCanStartRecording
        self.museCanStopRecording = museCanStopRecording
        self.museCanSaveNightOutcome = museCanSaveNightOutcome
        self.museRecordingSummary = museRecordingSummary
        self.onSetMorningOutcomeValue = onSetMorningOutcomeValue
        self.onScanForMuse = onScanForMuse
        self.onConnectToMuse = onConnectToMuse
        self.onDisconnectMuse = onDisconnectMuse
        self.onStartMuseRecording = onStartMuseRecording
        self.onStopMuseRecording = onStopMuseRecording
        self.onSaveMuseNightOutcome = onSaveMuseNightOutcome
        self.selectedSkinID = selectedSkinID
        _isMorningCheckInExpanded = State(initialValue: !morningOutcomeSelection.isComplete)
        _selectedMorningMetric = State(initialValue: .composite)
        _selectedNightMetric = State(initialValue: .microArousalRatePerHour)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: TelocareTheme.Spacing.lg) {
                    morningGreetingCard
                    morningCheckInSection
                    morningTrendSection
                    nightTrendSection
                    museSessionSection
                    insightsSummaryCard
                    nightRecordsSection
                }
                .padding(.horizontal, TelocareTheme.Spacing.md)
                .padding(.vertical, TelocareTheme.Spacing.lg)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: OutcomeRecord.self) { record in
                OutcomeDetailView(record: record, outcomesMetadata: outcomesMetadata)
                    .accessibilityIdentifier(AccessibilityID.exploreOutcomeDetailSheet)
            }
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
        .onChange(of: morningOutcomeSelection.isComplete) { _, isComplete in
            guard isComplete else { return }
            guard isMorningCheckInExpanded else { return }
            withAnimation(.spring(response: 0.3)) {
                isMorningCheckInExpanded = false
            }
        }
    }

    private func showRecordDetail(_ record: OutcomeRecord) {
        navigationPath.append(record)
    }

    // MARK: - Morning Greeting Card

    @ViewBuilder
    private var morningGreetingCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                Text(greetingText)
                    .font(TelocareTheme.Typography.largeTitle)
                    .foregroundStyle(TelocareTheme.charcoal)
                Text("How are you feeling this morning?")
                    .font(TelocareTheme.Typography.body)
                    .foregroundStyle(TelocareTheme.warmGray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    // MARK: - Morning Check-in Section

    @ViewBuilder
    private var morningCheckInSection: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isMorningCheckInExpanded.toggle()
                }
            } label: {
                HStack {
                    WarmSectionHeader(
                        title: "Morning check-in",
                        subtitle: "Night \(morningOutcomeSelection.nightID)"
                    )
                    Spacer()
                    Image(systemName: isMorningCheckInExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(TelocareTheme.warmGray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.exploreOutcomesMorningCheckInToggle)
            .accessibilityValue(isMorningCheckInExpanded ? "Expanded" : "Collapsed")

            if isMorningCheckInExpanded {
                VStack(spacing: TelocareTheme.Spacing.md) {
                    ForEach(MorningOutcomeField.allCases) { field in
                        EmojiRatingPicker(
                            field: field,
                            value: bindingForField(field)
                        )
                        .accessibilityIdentifier(field.accessibilityIdentifier)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func bindingForField(_ field: MorningOutcomeField) -> Binding<Int?> {
        Binding(
            get: { morningOutcomeSelection.value(for: field) },
            set: { onSetMorningOutcomeValue($0, field) }
        )
    }

    private var morningTrendPoints: [OutcomeTrendPoint] {
        OutcomeTrendDataBuilder()
            .morningPoints(from: morningStates, metric: selectedMorningMetric)
    }

    private var nightTrendPoints: [OutcomeTrendPoint] {
        OutcomeTrendDataBuilder()
            .nightPoints(from: outcomeRecords, metric: selectedNightMetric)
    }

    private var morningChartHeight: CGFloat {
        isMorningCheckInExpanded ? 170 : 280
    }

    private var morningYAxisValues: [Double] {
        [0, 2.5, 5, 7.5, 10]
    }

    private var nightChartYDomain: ClosedRange<Double> {
        if selectedNightMetric == .confidence {
            return 0...1
        }

        let maxValue = nightTrendPoints.map(\.value).max() ?? 0
        let paddedMax = maxValue * 1.1
        return 0...max(1, paddedMax)
    }

    private var morningSummaryText: String {
        guard let latest = morningTrendPoints.last else {
            return "No morning trend data in last 14 days."
        }

        return "Latest \(selectedMorningMetric.title): \(formattedMorningValue(latest.value)) on \(formattedDate(latest.date))."
    }

    private var morningDirectionText: String {
        "Lower is better. 😌 is best and 😫 is worst."
    }

    private var nightSummaryText: String {
        guard let latest = nightTrendPoints.last else {
            return "No night outcome data yet. This chart will populate when night outcomes are recorded."
        }

        return "Latest \(selectedNightMetric.title): \(formattedNightValue(latest.value)) on \(formattedDate(latest.date))."
    }

    private var nightDirectionText: String {
        switch selectedNightMetric {
        case .confidence:
            return "Direction: higher is better."
        case .microArousalRatePerHour, .microArousalCount:
            return "Direction: lower is better."
        }
    }

    private var morningChartAccessibilityValue: String {
        let layout = isMorningCheckInExpanded ? "Compact" : "Expanded"
        guard let latest = morningTrendPoints.last else {
            return "\(selectedMorningMetric.title), no data, \(layout), lower is better"
        }

        return "\(selectedMorningMetric.title), \(formattedMorningValue(latest.value)), \(morningEmoji(for: latest.value)), \(layout), lower is better"
    }

    private var nightChartAccessibilityValue: String {
        guard let latest = nightTrendPoints.last else {
            return "\(selectedNightMetric.title), no data"
        }

        return "\(selectedNightMetric.title), \(formattedNightValue(latest.value)), \(nightDirectionText)"
    }

    @ViewBuilder
    private var morningTrendSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                HStack(alignment: .top, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Morning trend", subtitle: "Last 14 days")
                    Spacer()
                    Picker("Morning metric", selection: $selectedMorningMetric) {
                        ForEach(MorningTrendMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if morningTrendPoints.isEmpty {
                    Text("No morning trend data in last 14 days.")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                } else {
                    Chart(morningTrendPoints) { point in
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value(selectedMorningMetric.title, point.value)
                        )
                        .foregroundStyle(TelocareTheme.coral)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.date),
                            y: .value(selectedMorningMetric.title, point.value)
                        )
                        .foregroundStyle(TelocareTheme.coral)
                        .symbolSize(36)
                    }
                    .frame(height: morningChartHeight)
                    .chartYScale(domain: 0...10)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: morningYAxisValues) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let rawValue = value.as(Double.self) {
                                    Text(morningYAxisLabel(for: rawValue))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) {
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                }

                Text(morningSummaryText)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)

                Text(morningDirectionText)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .animation(.spring(response: 0.3), value: isMorningCheckInExpanded)
        .accessibilityIdentifier(AccessibilityID.exploreOutcomesMorningChart)
        .accessibilityLabel("Morning outcomes trend chart")
        .accessibilityValue(morningChartAccessibilityValue)
    }

    @ViewBuilder
    private var nightTrendSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                HStack(alignment: .top, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Night trend", subtitle: "Last 14 days")
                    Spacer()
                    Picker("Night metric", selection: $selectedNightMetric) {
                        ForEach(NightTrendMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if nightTrendPoints.isEmpty {
                    Text("No night outcome data yet. This chart will populate when night outcomes are recorded.")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                } else {
                    Chart(nightTrendPoints) { point in
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value(selectedNightMetric.title, point.value)
                        )
                        .foregroundStyle(TelocareTheme.success)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.date),
                            y: .value(selectedNightMetric.title, point.value)
                        )
                        .foregroundStyle(TelocareTheme.success)
                    }
                    .frame(height: 200)
                    .chartYScale(domain: nightChartYDomain)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) {
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                }

                Text(nightSummaryText)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)

                Text(nightDirectionText)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.exploreOutcomesNightChart)
        .accessibilityLabel("Night outcomes trend chart")
        .accessibilityValue(nightChartAccessibilityValue)
    }

    @ViewBuilder
    private var museSessionSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                WarmSectionHeader(
                    title: "Muse session",
                    subtitle: "Manual overnight recording"
                )

                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    statusRow(
                        title: "Connection",
                        value: museConnectionStatusText,
                        accessibilityID: AccessibilityID.exploreMuseConnectionStatus
                    )
                    statusRow(
                        title: "Recording",
                        value: museRecordingStatusText,
                        accessibilityID: AccessibilityID.exploreMuseRecordingStatus
                    )
                }

                if let summaryText = museSummaryText {
                    Text(summaryText)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    actionButton(
                        title: "Scan",
                        accessibilityID: AccessibilityID.exploreMuseScanButton,
                        isEnabled: museCanScan,
                        action: onScanForMuse
                    )
                    actionButton(
                        title: "Connect",
                        accessibilityID: AccessibilityID.exploreMuseConnectButton,
                        isEnabled: museCanConnect,
                        action: onConnectToMuse
                    )
                    actionButton(
                        title: "Disconnect",
                        accessibilityID: AccessibilityID.exploreMuseDisconnectButton,
                        isEnabled: museCanDisconnect,
                        action: onDisconnectMuse
                    )
                    actionButton(
                        title: "Start recording",
                        accessibilityID: AccessibilityID.exploreMuseStartRecordingButton,
                        isEnabled: museCanStartRecording,
                        action: onStartMuseRecording
                    )
                    actionButton(
                        title: "Stop recording",
                        accessibilityID: AccessibilityID.exploreMuseStopRecordingButton,
                        isEnabled: museCanStopRecording,
                        action: onStopMuseRecording
                    )
                    actionButton(
                        title: "Save night outcome",
                        accessibilityID: AccessibilityID.exploreMuseSaveNightOutcomeButton,
                        isEnabled: museCanSaveNightOutcome,
                        action: onSaveMuseNightOutcome
                    )
                }

                Text(museSessionFeedback)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.exploreMuseFeedbackText)

                Text(museDisclaimerText)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.exploreMuseDisclaimerText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.exploreMuseSessionSection)
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        accessibilityID: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(TelocareTheme.Typography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(TelocareTheme.coral)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private func statusRow(
        title: String,
        value: String,
        accessibilityID: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.charcoal)
            Spacer()
            Text(value)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.warmGray)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID)
    }

    private var museSummaryText: String? {
        guard let summary = museRecordingSummary else {
            return nil
        }

        let rateText: String
        if let rate = summary.microArousalRatePerHour {
            rateText = String(format: "%.2f/hr", rate)
        } else {
            rateText = "n/a"
        }

        return "Microarousals \(Int(summary.microArousalCount.rounded())), rate \(rateText), confidence \(String(format: "%.2f", summary.confidence))."
    }

    private func formattedMorningValue(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formattedNightValue(_ value: Double) -> String {
        if selectedNightMetric == .confidence {
            return String(format: "%.2f", value)
        }

        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func morningEmoji(for value: Double) -> String {
        switch value {
        case ..<1.25:
            return "😌"
        case ..<3.75:
            return "🙂"
        case ..<6.25:
            return "😐"
        case ..<8.75:
            return "😣"
        default:
            return "😫"
        }
    }

    private func morningYAxisLabel(for value: Double) -> String {
        switch value {
        case ..<1.25:
            return "😌"
        case ..<3.75:
            return "🙂"
        case ..<6.25:
            return "😐"
        case ..<8.75:
            return "😣"
        default:
            return "😫"
        }
    }

    // MARK: - Insights Summary Card

    @ViewBuilder
    private var insightsSummaryCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                WarmSectionHeader(title: "Your progress")

                HStack(spacing: TelocareTheme.Spacing.lg) {
                    insightMetric(
                        icon: "shield.fill",
                        value: "\(outcomes.shieldScore)",
                        label: "Shield score"
                    )
                    insightMetric(
                        icon: "arrow.up.right",
                        value: "\(outcomes.burdenTrendPercent)%",
                        label: "Burden trend"
                    )
                }

                Divider()
                    .background(TelocareTheme.peach)

                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(TelocareTheme.warmOrange)
                    Text("Top contributor: \(outcomes.topContributor)")
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.charcoal)
                }
            }
        }
    }

    @ViewBuilder
    private func insightMetric(icon: String, value: String, label: String) -> some View {
        VStack(spacing: TelocareTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(TelocareTheme.coral)
            Text(value)
                .font(TelocareTheme.Typography.title)
                .foregroundStyle(TelocareTheme.charcoal)
            Text(label)
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Night Records Section

    @ViewBuilder
    private var nightRecordsSection: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
            WarmSectionHeader(
                title: "Recent nights",
                subtitle: outcomeRecords.isEmpty ? nil : "Tap to see details"
            )

            if outcomeRecords.isEmpty {
                emptyNightsPlaceholder
            } else {
                ForEach(outcomeRecords.prefix(5)) { record in
                    Button { showRecordDetail(record) } label: {
                        NightRecordCard(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyNightsPlaceholder: some View {
        WarmCard {
            HStack(spacing: TelocareTheme.Spacing.md) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(TelocareTheme.muted)
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                    Text("No night data yet")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)
                    Text("Your sleep outcomes will appear here as they're recorded.")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                }
            }
        }
    }
}

private struct NightRecordCard: View {
    let record: OutcomeRecord

    var body: some View {
        WarmCard(padding: TelocareTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                    Text(record.id)
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)
                    if let rate = record.microArousalRatePerHour {
                        Text("Arousal rate: \(String(format: "%.1f", rate))/hr")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(TelocareTheme.muted)
            }
        }
    }
}


private struct OutcomeDetailView: View {
    let record: OutcomeRecord
    let outcomesMetadata: OutcomesMetadata

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                Text("Night \(record.id)")
                    .font(.largeTitle.bold())
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)

                measurementsCard
                interpretationCard

                if !outcomeNodeEvidence.isEmpty {
                    evidenceCard
                }
            }
            .padding(TelocareTheme.Spacing.md)
        }
        .background(TelocareTheme.sand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Measurements Card

    @ViewBuilder
    private var measurementsCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Measurements")

                DetailRow(label: "Night", value: record.id)
                DetailRow(label: "Arousal rate/hour", value: formatted(record.microArousalRatePerHour))
                DetailRow(label: "Arousal count", value: formatted(record.microArousalCount))
                DetailRow(label: "Confidence", value: formatted(record.confidence))
                DetailRow(label: "Source", value: record.source ?? "Unknown")
            }
        }
    }

    // MARK: - Interpretation Card

    @ViewBuilder
    private var interpretationCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "How to read this")

                if metricsForDisplay.isEmpty {
                    Text("Outcome metadata is not available yet.")
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.warmGray)
                } else {
                    ForEach(metricsForDisplay, id: \.id) { metric in
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text(metric.label)
                                .font(TelocareTheme.Typography.headline)
                                .foregroundStyle(TelocareTheme.charcoal)
                            Text(metric.description)
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)

                            HStack(spacing: TelocareTheme.Spacing.md) {
                                WarmChip(text: metric.unit)
                                WarmChip(text: metric.direction.replacingOccurrences(of: "_", with: " "))
                            }
                        }
                        .padding(.vertical, TelocareTheme.Spacing.xs)

                        if metric.id != metricsForDisplay.last?.id {
                            Divider()
                                .background(TelocareTheme.peach)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Evidence Card

    @ViewBuilder
    private var evidenceCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Outcome pathway evidence")

                ForEach(outcomeNodeEvidence) { node in
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Text(node.label)
                            .font(TelocareTheme.Typography.headline)
                            .foregroundStyle(TelocareTheme.charcoal)

                        if let evidence = node.evidence {
                            DetailRow(label: "Evidence", value: evidence)
                        }
                        if let stat = node.stat {
                            DetailRow(label: "Statistic", value: stat)
                        }
                        if let citation = node.citation {
                            Text(citation)
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                                .italic()
                        }
                        if let mechanism = node.mechanism {
                            Text(mechanism)
                                .font(TelocareTheme.Typography.body)
                                .foregroundStyle(TelocareTheme.charcoal)
                        }
                    }
                    .padding(.vertical, TelocareTheme.Spacing.xs)

                    if node.id != outcomeNodeEvidence.last?.id {
                        Divider()
                            .background(TelocareTheme.peach)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "Not recorded" }
        return String(format: "%.2f", value)
    }

    private var metricsForDisplay: [OutcomeMetricDefinition] {
        outcomesMetadata.metrics.filter {
            $0.id == "microArousalRatePerHour"
                || $0.id == "microArousalCount"
                || $0.id == "confidence"
        }
    }

    private var outcomeNodeEvidence: [OutcomeNodeMetadata] {
        outcomesMetadata.nodes
    }
}

private struct ExploreSituationScreen: View {
    let situation: SituationSummary
    let graphData: CausalGraphData
    let displayFlags: GraphDisplayFlags
    let focusedNodeID: String?
    let graphSelectionText: String
    let onGraphEvent: (GraphEvent) -> Void
    let onAction: (ExploreContextAction) -> Void
    let onShowInterventionsChanged: (Bool) -> Void
    let onShowFeedbackEdgesChanged: (Bool) -> Void
    let onShowProtectiveEdgesChanged: (Bool) -> Void
    let onToggleNodeDeactivated: (String) -> Void
    let onToggleEdgeDeactivated: (String, String, String?, String?) -> Void
    let selectedSkinID: TelocareSkinID

    @State private var isOptionsPresented = false
    @State private var selectedGraphSelection: SituationGraphSelection?

    var body: some View {
        NavigationStack {
            GraphWebView(
                graphData: graphData,
                graphSkin: TelocareTheme.graphSkin,
                displayFlags: displayFlags,
                focusedNodeID: focusedNodeID,
                onEvent: handleGraphEvent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
            .padding(12)
            .accessibilityIdentifier(AccessibilityID.graphWebView)
            .onLongPressGesture {
                onAction(.refineNode)
            }
            .contextMenu {
                ForEach(ExploreContextAction.allCases) { action in
                    Button(action.title) {
                        onAction(action)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(graphSelectionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(24)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(AccessibilityID.graphSelectionText)
            }
            .navigationTitle("Situation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {
                        isOptionsPresented = true
                    }
                    .accessibilityIdentifier(AccessibilityID.exploreSituationEditButton)
                }
            }
            .sheet(isPresented: $isOptionsPresented) {
                SituationOptionsSheet(
                    situation: situation,
                    graphSelectionText: graphSelectionText,
                    displayFlags: displayFlags,
                    onAction: onAction,
                    onShowInterventionsChanged: onShowInterventionsChanged,
                    onShowFeedbackEdgesChanged: onShowFeedbackEdgesChanged,
                    onShowProtectiveEdgesChanged: onShowProtectiveEdgesChanged
                )
                .accessibilityIdentifier(AccessibilityID.exploreSituationOptionsSheet)
            }
            .sheet(item: $selectedGraphSelection) { selection in
                SituationGraphDetailSheet(
                    detail: detail(for: selection),
                    onToggleNodeDeactivated: onToggleNodeDeactivated,
                    onToggleEdgeDeactivated: onToggleEdgeDeactivated
                )
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier(AccessibilityID.exploreDetailsSheet)
            }
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
    }

    private func handleGraphEvent(_ event: GraphEvent) {
        onGraphEvent(event)

        switch event {
        case .nodeSelected(let id, let label):
            selectedGraphSelection = .node(
                nodeID: id,
                fallbackLabel: label
            )
        case .edgeSelected(let sourceID, let targetID, let sourceLabel, let targetLabel, let label, let edgeType):
            let detail = edgeDetail(
                sourceID: sourceID,
                targetID: targetID,
                sourceLabel: sourceLabel,
                targetLabel: targetLabel,
                label: label,
                edgeType: edgeType
            )
            selectedGraphSelection = .edge(
                SituationEdgeSelection(
                    sourceID: sourceID,
                    targetID: targetID,
                    sourceLabel: sourceLabel,
                    targetLabel: targetLabel,
                    label: detail.label,
                    edgeType: detail.edgeType
                )
            )
        case .graphReady, .viewportChanged, .renderError:
            return
        }
    }

    private func detail(for selection: SituationGraphSelection) -> SituationGraphDetail {
        switch selection {
        case .node(let nodeID, let fallbackLabel):
            return .node(nodeDetail(forNodeID: nodeID, fallbackLabel: fallbackLabel))
        case .edge(let edgeSelection):
            return .edge(
                edgeDetail(
                    sourceID: edgeSelection.sourceID,
                    targetID: edgeSelection.targetID,
                    sourceLabel: edgeSelection.sourceLabel,
                    targetLabel: edgeSelection.targetLabel,
                    label: edgeSelection.label,
                    edgeType: edgeSelection.edgeType
                )
            )
        }
    }

    private func nodeDetail(forNodeID id: String, fallbackLabel: String) -> SituationNodeDetail {
        guard let node = graphData.nodes.first(where: { $0.data.id == id })?.data else {
            return SituationNodeDetail(
                id: id,
                label: fallbackLabel,
                styleClass: nil,
                tier: nil,
                evidence: nil,
                statistic: nil,
                citation: nil,
                mechanism: nil,
                isDeactivated: false
            )
        }

        return SituationNodeDetail(
            id: node.id,
            label: firstLine(node.label),
            styleClass: node.styleClass,
            tier: node.tier,
            evidence: node.tooltip?.evidence,
            statistic: node.tooltip?.stat,
            citation: node.tooltip?.citation,
            mechanism: node.tooltip?.mechanism,
            isDeactivated: node.isDeactivated == true
        )
    }

    private func edgeDetail(
        sourceID: String,
        targetID: String,
        sourceLabel: String,
        targetLabel: String,
        label: String?,
        edgeType: String?
    ) -> SituationEdgeDetail {
        let nodeLabelByID = Dictionary(
            uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, firstLine($0.data.label)) }
        )

        let nodeByID = Dictionary(
            uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data) }
        )

        let matchedEdge = graphData.edges.first {
            edgeIdentityMatches(
                edge: $0.data,
                sourceID: sourceID,
                targetID: targetID,
                label: label,
                edgeType: edgeType
            )
        }?.data ?? graphData.edges.first {
            let edgeSourceLabel = nodeLabelByID[$0.data.source] ?? $0.data.source
            let edgeTargetLabel = nodeLabelByID[$0.data.target] ?? $0.data.target
            return edgeSourceLabel == sourceLabel
                && edgeTargetLabel == targetLabel
                && normalizedOptionalString($0.data.label) == normalizedOptionalString(label)
                && normalizedOptionalString($0.data.edgeType) == normalizedOptionalString(edgeType)
        }?.data

        let isExplicitlyDeactivated = matchedEdge?.isDeactivated == true
        let sourceIsDeactivated = nodeByID[sourceID]?.isDeactivated == true
        let targetIsDeactivated = nodeByID[targetID]?.isDeactivated == true

        return SituationEdgeDetail(
            sourceID: sourceID,
            targetID: targetID,
            sourceLabel: sourceLabel,
            targetLabel: targetLabel,
            label: matchedEdge?.label ?? label,
            edgeType: matchedEdge?.edgeType ?? edgeType,
            tooltip: matchedEdge?.tooltip,
            edgeColor: matchedEdge?.edgeColor,
            isExplicitlyDeactivated: isExplicitlyDeactivated,
            isEffectivelyDeactivated: isExplicitlyDeactivated || sourceIsDeactivated || targetIsDeactivated
        )
    }

    private func firstLine(_ value: String) -> String {
        value.components(separatedBy: "\n").first ?? value
    }
    private func edgeIdentityMatches(
        edge: GraphEdgeData,
        sourceID: String,
        targetID: String,
        label: String?,
        edgeType: String?
    ) -> Bool {
        guard edge.source == sourceID else { return false }
        guard edge.target == targetID else { return false }
        guard normalizedOptionalString(edge.label) == normalizedOptionalString(label) else { return false }
        return normalizedOptionalString(edge.edgeType) == normalizedOptionalString(edgeType)
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

private enum SituationGraphSelection: Identifiable, Equatable {
    case node(nodeID: String, fallbackLabel: String)
    case edge(SituationEdgeSelection)

    var id: String {
        switch self {
        case .node(let nodeID, _):
            return "node:\(nodeID)"
        case .edge(let edgeSelection):
            return "edge:\(edgeSelection.id)"
        }
    }
}

private struct SituationEdgeSelection: Equatable {
    let sourceID: String
    let targetID: String
    let sourceLabel: String
    let targetLabel: String
    let label: String?
    let edgeType: String?

    var id: String {
        let normalizedLabel = label ?? ""
        let normalizedType = edgeType ?? ""
        return "\(sourceID)|\(targetID)|\(normalizedLabel)|\(normalizedType)"
    }
}

private enum SituationGraphDetail: Equatable {
    case node(SituationNodeDetail)
    case edge(SituationEdgeDetail)
}

private struct SituationNodeDetail: Equatable {
    let id: String
    let label: String
    let styleClass: String?
    let tier: Int?
    let evidence: String?
    let statistic: String?
    let citation: String?
    let mechanism: String?
    let isDeactivated: Bool
}

private struct SituationEdgeDetail: Equatable {
    let sourceID: String
    let targetID: String
    let sourceLabel: String
    let targetLabel: String
    let label: String?
    let edgeType: String?
    let tooltip: String?
    let edgeColor: String?
    let isExplicitlyDeactivated: Bool
    let isEffectivelyDeactivated: Bool
}

private struct SituationGraphDetailSheet: View {
    let detail: SituationGraphDetail
    let onToggleNodeDeactivated: (String) -> Void
    let onToggleEdgeDeactivated: (String, String, String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                    switch detail {
                    case .node(let node):
                        nodeContent(node)
                    case .edge(let edge):
                        edgeContent(edge)
                    }
                }
                .padding(TelocareTheme.Spacing.md)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(TelocareTheme.coral)
                }
            }
        }
    }

    @ViewBuilder
    private func nodeContent(_ node: SituationNodeDetail) -> some View {
        HStack(spacing: TelocareTheme.Spacing.sm) {
            Circle()
                .fill(accentColor(for: node.styleClass))
                .frame(width: 12, height: 12)
            Text(node.label)
                .font(.title2.bold())
                .foregroundStyle(TelocareTheme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        }

        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Node Info")
                DetailRow(label: "Type", value: displayName(for: node.styleClass))
                if let tier = node.tier {
                    DetailRow(label: "Tier", value: String(tier))
                }
                DetailRow(
                    label: "Status",
                    value: node.isDeactivated ? "Deactivated" : "Active"
                )
                .accessibilityIdentifier(AccessibilityID.exploreDetailsNodeDeactivationStatus)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .stroke(accentColor(for: node.styleClass), lineWidth: 2)
        )

        WarmCard {
            Button(node.isDeactivated ? "Reactivate node" : "Deactivate node") {
                onToggleNodeDeactivated(node.id)
            }
            .font(TelocareTheme.Typography.body.weight(.semibold))
            .foregroundStyle(TelocareTheme.charcoal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityID.exploreDetailsNodeDeactivationButton)
            .accessibilityValue(node.isDeactivated ? "Deactivated" : "Active")
        }

        if node.evidence != nil || node.statistic != nil || node.citation != nil || node.mechanism != nil {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Evidence")
                    if let evidence = node.evidence {
                        DetailRow(label: "Level", value: evidence)
                    }
                    if let statistic = node.statistic {
                        DetailRow(label: "Statistic", value: statistic)
                    }
                    if let citation = node.citation {
                        DetailRow(label: "Citation", value: citation)
                    }
                    if let mechanism = node.mechanism {
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text("Mechanism")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                            Text(mechanism)
                                .font(TelocareTheme.Typography.body)
                                .foregroundStyle(TelocareTheme.charcoal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func edgeContent(_ edge: SituationEdgeDetail) -> some View {
        let edgeAccent = edgeAccentColor(for: edge.edgeType, color: edge.edgeColor)

        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(edgeAccent)
                    .frame(width: 24, height: 4)
                Text("Link")
                    .font(.title2.bold())
                    .foregroundStyle(TelocareTheme.charcoal)
            }
            Text("\(edge.sourceLabel) → \(edge.targetLabel)")
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.warmGray)
                .fixedSize(horizontal: false, vertical: true)
        }

        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Details")
                if let label = edge.label, !label.isEmpty {
                    DetailRow(label: "Label", value: label)
                }
                if let edgeType = edge.edgeType {
                    DetailRow(label: "Type", value: edgeType.capitalized)
                }
                DetailRow(
                    label: "Status",
                    value: edgeStatusText(edge)
                )
                .accessibilityIdentifier(AccessibilityID.exploreDetailsEdgeDeactivationStatus)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .stroke(edgeAccent, lineWidth: 2)
        )

        WarmCard {
            Button(edge.isExplicitlyDeactivated ? "Reactivate link" : "Deactivate link") {
                onToggleEdgeDeactivated(
                    edge.sourceID,
                    edge.targetID,
                    edge.label,
                    edge.edgeType
                )
            }
            .font(TelocareTheme.Typography.body.weight(.semibold))
            .foregroundStyle(TelocareTheme.charcoal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityID.exploreDetailsEdgeDeactivationButton)
            .accessibilityValue(edgeStatusText(edge))
        }

        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Explanation")
                Text(edge.tooltip ?? "No explanation is available for this link yet.")
                    .font(TelocareTheme.Typography.body)
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func edgeStatusText(_ edge: SituationEdgeDetail) -> String {
        if edge.isEffectivelyDeactivated {
            return "Deactivated"
        }

        return "Active"
    }

    private func accentColor(for styleClass: String?) -> Color {
        switch styleClass?.lowercased() {
        case "robust":
            return TelocareTheme.robust
        case "moderate":
            return TelocareTheme.moderate
        case "preliminary":
            return TelocareTheme.preliminary
        case "mechanism":
            return TelocareTheme.mechanism
        case "symptom":
            return TelocareTheme.symptom
        case "intervention":
            return TelocareTheme.intervention
        default:
            return TelocareTheme.warmGray
        }
    }

    private func edgeAccentColor(for edgeType: String?, color: String?) -> Color {
        if let normalizedHex = normalizedHexColor(color) {
            switch normalizedHex {
            case "1b4332":
                return TelocareTheme.graphEdgeProtective
            case "065f46":
                return TelocareTheme.graphEdgeIntervention
            case "1e3a5f":
                return TelocareTheme.graphEdgeMechanism
            case "b45309":
                return TelocareTheme.graphEdgeCausal
            default:
                break
            }
        }

        if let color = color?.lowercased() {
            if color.contains("green") || color.contains("protective") {
                return TelocareTheme.graphEdgeProtective
            }
            if color.contains("red") || color.contains("harmful") {
                return TelocareTheme.symptom
            }
            if color.contains("blue") {
                return TelocareTheme.graphEdgeMechanism
            }
        }

        switch edgeType?.lowercased() {
        case "protective", "inhibits":
            return TelocareTheme.graphEdgeProtective
        case "causal", "causes", "triggers":
            return TelocareTheme.graphEdgeCausal
        case "feedback":
            return TelocareTheme.graphEdgeFeedback
        case "dashed":
            return TelocareTheme.graphEdgeMechanism
        default:
            return TelocareTheme.warmGray
        }
    }

    private func normalizedHexColor(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: "")

        guard normalized.count == 6 else {
            return nil
        }

        return normalized
    }

    private func displayName(for styleClass: String?) -> String {
        switch styleClass?.lowercased() {
        case "robust":
            return "Robust Evidence"
        case "moderate":
            return "Moderate Evidence"
        case "preliminary":
            return "Preliminary Evidence"
        case "mechanism":
            return "Mechanism"
        case "symptom":
            return "Symptom"
        case "intervention":
            return "Intervention"
        default:
            return styleClass?.capitalized ?? "Unknown"
        }
    }
}

private struct SituationOptionsSheet: View {
    let situation: SituationSummary
    let graphSelectionText: String
    let displayFlags: GraphDisplayFlags
    let onAction: (ExploreContextAction) -> Void
    let onShowInterventionsChanged: (Bool) -> Void
    let onShowFeedbackEdgesChanged: (Bool) -> Void
    let onShowProtectiveEdgesChanged: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(graphSelectionText)
                        .foregroundStyle(TelocareTheme.charcoal)
                    LabeledContent("Focused node", value: situation.focusedNode)
                        .foregroundStyle(TelocareTheme.charcoal)
                    LabeledContent("Visible hotspots", value: "\(situation.visibleHotspots)")
                        .foregroundStyle(TelocareTheme.charcoal)
                } header: {
                    Text("Selection")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }

                Section {
                    Toggle(
                        "Show intervention nodes",
                        isOn: Binding(
                            get: { displayFlags.showInterventionNodes },
                            set: onShowInterventionsChanged
                        )
                    )
                    .tint(TelocareTheme.coral)
                    .accessibilityIdentifier(AccessibilityID.exploreToggleInterventions)

                    Toggle(
                        "Show feedback edges",
                        isOn: Binding(
                            get: { displayFlags.showFeedbackEdges },
                            set: onShowFeedbackEdgesChanged
                        )
                    )
                    .tint(TelocareTheme.coral)
                    .accessibilityIdentifier(AccessibilityID.exploreToggleFeedbackEdges)

                    Toggle(
                        "Show protective edges",
                        isOn: Binding(
                            get: { displayFlags.showProtectiveEdges },
                            set: onShowProtectiveEdgesChanged
                        )
                    )
                    .tint(TelocareTheme.coral)
                    .accessibilityIdentifier(AccessibilityID.exploreToggleProtectiveEdges)
                } header: {
                    Text("Display")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }

                Section {
                    ForEach(ExploreContextAction.allCases) { action in
                        Button(action.title) {
                            onAction(action)
                        }
                        .foregroundStyle(TelocareTheme.coral)
                        .accessibilityIdentifier(action.accessibilityIdentifier)
                    }
                } header: {
                    Text("Actions")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(TelocareTheme.sand)
            .navigationTitle("Situation Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(TelocareTheme.coral)
                }
            }
        }
    }
}

private struct ExploreInputsScreen: View {
    let inputs: [InputStatus]
    let graphData: CausalGraphData
    let onToggleCheckedToday: (String) -> Void
    let onIncrementDose: (String) -> Void
    let onDecrementDose: (String) -> Void
    let onResetDose: (String) -> Void
    let onUpdateDoseSettings: (String, Double, Double) -> Void
    let onConnectAppleHealth: (String) -> Void
    let onDisconnectAppleHealth: (String) -> Void
    let onRefreshAppleHealth: (String) async -> Void
    let onRefreshAllAppleHealth: () async -> Void
    let onToggleActive: (String) -> Void
    let selectedSkinID: TelocareSkinID

    @State private var navigationPath = NavigationPath()
    @State private var filterMode: InputFilterMode

    init(
        inputs: [InputStatus],
        graphData: CausalGraphData,
        onToggleCheckedToday: @escaping (String) -> Void,
        onIncrementDose: @escaping (String) -> Void,
        onDecrementDose: @escaping (String) -> Void,
        onResetDose: @escaping (String) -> Void,
        onUpdateDoseSettings: @escaping (String, Double, Double) -> Void,
        onConnectAppleHealth: @escaping (String) -> Void,
        onDisconnectAppleHealth: @escaping (String) -> Void,
        onRefreshAppleHealth: @escaping (String) async -> Void,
        onRefreshAllAppleHealth: @escaping () async -> Void,
        onToggleActive: @escaping (String) -> Void,
        selectedSkinID: TelocareSkinID
    ) {
        self.inputs = inputs
        self.graphData = graphData
        self.onToggleCheckedToday = onToggleCheckedToday
        self.onIncrementDose = onIncrementDose
        self.onDecrementDose = onDecrementDose
        self.onResetDose = onResetDose
        self.onUpdateDoseSettings = onUpdateDoseSettings
        self.onConnectAppleHealth = onConnectAppleHealth
        self.onDisconnectAppleHealth = onDisconnectAppleHealth
        self.onRefreshAppleHealth = onRefreshAppleHealth
        self.onRefreshAllAppleHealth = onRefreshAllAppleHealth
        self.onToggleActive = onToggleActive
        self.selectedSkinID = selectedSkinID
        _filterMode = State(initialValue: inputs.contains(where: \.isActive) ? .pending : .available)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                progressOverviewHeader
                filterPillsSection
                inputsContent
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Interventions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { inputID in
                if let input = inputStatus(for: inputID) {
                    InputDetailView(
                        input: input,
                        graphData: graphData,
                        onIncrementDose: onIncrementDose,
                        onDecrementDose: onDecrementDose,
                        onResetDose: onResetDose,
                        onUpdateDoseSettings: onUpdateDoseSettings,
                        onConnectAppleHealth: onConnectAppleHealth,
                        onDisconnectAppleHealth: onDisconnectAppleHealth,
                        onRefreshAppleHealth: onRefreshAppleHealth,
                        onToggleActive: onToggleActive
                    )
                    .accessibilityIdentifier(AccessibilityID.exploreInputDetailSheet)
                } else {
                    ContentUnavailableView("Intervention unavailable", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
    }

    private func showInputDetail(_ input: InputStatus) {
        navigationPath.append(input.id)
    }

    private func inputStatus(for inputID: String) -> InputStatus? {
        inputs.first { $0.id == inputID }
    }

    // MARK: - Progress Overview Header

    @ViewBuilder
    private var progressOverviewHeader: some View {
        WarmCard {
            HStack(spacing: TelocareTheme.Spacing.lg) {
                WarmProgressRing(progress: overallCompletion, size: 64, lineWidth: 8)

                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                    Text("Today's progress")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)
                    Text("\(checkedTodayCount) of \(visibleInputs.count) completed")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)

                    if checkedTodayCount == visibleInputs.count && !visibleInputs.isEmpty {
                        Label("All done!", systemImage: "checkmark.circle.fill")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.success)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, TelocareTheme.Spacing.md)
        .padding(.top, TelocareTheme.Spacing.md)
    }

    private var checkedTodayCount: Int {
        visibleInputs.filter(\.isCheckedToday).count
    }

    private var overallCompletion: Double {
        guard !visibleInputs.isEmpty else { return 0 }
        return Double(checkedTodayCount) / Double(visibleInputs.count)
    }

    // MARK: - Filter Pills

    @ViewBuilder
    private var filterPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                ForEach(InputFilterMode.allCases, id: \.self) { mode in
                    FilterPill(
                        title: mode.title,
                        count: countFor(mode),
                        isSelected: filterMode == mode,
                        action: { filterMode = mode }
                    )
                }
            }
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.vertical, TelocareTheme.Spacing.sm)
        }
    }

    private func countFor(_ mode: InputFilterMode) -> Int {
        switch mode {
        case .pending:
            return inputs.filter { $0.isActive && !$0.isCheckedToday }.count
        case .completed:
            return inputs.filter { $0.isActive && $0.isCheckedToday }.count
        case .available:
            return inputs.filter { !$0.isActive }.count
        }
    }

    // MARK: - Inputs Content

    @ViewBuilder
    private var inputsContent: some View {
        if filteredInputs.isEmpty {
            emptyStatePlaceholder
        } else {
            ScrollView {
                LazyVStack(spacing: TelocareTheme.Spacing.sm) {
                    ForEach(filteredInputs) { input in
                        InputCard(
                            input: input,
                            onToggle: { onToggleCheckedToday(input.id) },
                            onIncrementDose: { onIncrementDose(input.id) },
                            onToggleActive: { onToggleActive(input.id) },
                            onShowDetails: { showInputDetail(input) }
                        )
                    }
                }
                .padding(TelocareTheme.Spacing.md)
            }
            .refreshable {
                await onRefreshAllAppleHealth()
            }
        }
    }

    /// Inputs sorted by impact score (most useful first)
    private var sortedInputs: [InputStatus] {
        InputScoring.sortedByImpact(inputs: inputs, graphData: graphData)
    }

    private var filteredInputs: [InputStatus] {
        switch filterMode {
        case .pending:
            return sortedInputs.filter { $0.isActive && !$0.isCheckedToday }
        case .completed:
            return sortedInputs.filter { $0.isActive && $0.isCheckedToday }
        case .available:
            return sortedInputs.filter { !$0.isActive }
        }
    }

    private var visibleInputs: [InputStatus] {
        sortedInputs.filter(\.isActive)
    }

    @ViewBuilder
    private var emptyStatePlaceholder: some View {
        VStack(spacing: TelocareTheme.Spacing.md) {
            Spacer()
            Image(systemName: filterMode == .completed ? "checkmark.circle" : "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(TelocareTheme.muted)
            Text(emptyStateMessage)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.warmGray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(TelocareTheme.Spacing.xl)
    }

    private var emptyStateMessage: String {
        switch filterMode {
        case .pending:
            return "No active interventions left for today."
        case .completed:
            return "Nothing completed yet today.\nTap an intervention to make progress."
        case .available:
            return "No available interventions."
        }
    }
}

// MARK: - Filter Mode

private enum InputFilterMode: CaseIterable {
    case pending, completed, available

    var title: String {
        switch self {
        case .pending:
            return "To do"
        case .completed:
            return "Done"
        case .available:
            return "Available"
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TelocareTheme.Spacing.xs) {
                Text(title)
                Text("\(count)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : TelocareTheme.muted.opacity(0.3))
                    .clipShape(Capsule())
            }
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(isSelected ? .white : TelocareTheme.charcoal)
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.vertical, TelocareTheme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? TelocareTheme.coral : TelocareTheme.cream)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Input Card

private struct InputCard: View {
    let input: InputStatus
    let onToggle: () -> Void
    let onIncrementDose: () -> Void
    let onToggleActive: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        WarmCard(padding: 0) {
            HStack(spacing: 0) {
                primaryControl
                    .padding(.leading, TelocareTheme.Spacing.sm)
                    .padding(.vertical, TelocareTheme.Spacing.sm)

                Button(action: onShowDetails) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.name)
                                .font(TelocareTheme.Typography.headline)
                                .foregroundStyle(input.isActive && input.isCheckedToday && input.trackingMode == .binary ? TelocareTheme.muted : TelocareTheme.charcoal)
                                .strikethrough(input.isActive && input.isCheckedToday && input.trackingMode == .binary)

                            HStack(spacing: TelocareTheme.Spacing.sm) {
                                if input.trackingMode == .binary {
                                    WeeklyProgressBar(completion: input.completion)
                                } else if let doseState = input.doseState {
                                    Text(doseSummaryText(for: doseState))
                                        .font(TelocareTheme.Typography.caption)
                                        .foregroundStyle(TelocareTheme.warmGray)
                                }

                                if let evidence = input.evidenceLevel {
                                    EvidenceBadge(level: evidence)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(TelocareTheme.muted)
                    }
                    .padding(.horizontal, TelocareTheme.Spacing.sm)
                    .padding(.vertical, TelocareTheme.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if !input.isActive {
            Button(action: onToggleActive) {
                ZStack {
                    RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                        .fill(TelocareTheme.cream)
                    RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                        .stroke(TelocareTheme.coral, lineWidth: 1.5)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TelocareTheme.coral)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start tracking \(input.name)")
            .accessibilityHint("Adds this intervention to your active list.")
        } else {
            switch input.trackingMode {
            case .binary:
                Button(action: onToggle) {
                    ZStack {
                        RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                            .fill(input.isCheckedToday ? TelocareTheme.coral : TelocareTheme.peach)
                        if input.isCheckedToday {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(input.isCheckedToday ? "Uncheck \(input.name)" : "Check \(input.name)")
                .accessibilityHint("Marks this intervention as done for today.")

            case .dose:
                if let doseState = input.doseState {
                    Button(action: onIncrementDose) {
                        DoseCompletionRing(state: doseState, size: 34, lineWidth: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.exploreInputDoseIncrement)
                    .accessibilityLabel("Increment \(input.name)")
                    .accessibilityValue("\(doseSummaryText(for: doseState)).")
                    .accessibilityHint("Adds one increment toward today's goal.")
                }
            }
        }
    }

    private func doseSummaryText(for state: InputDoseState) -> String {
        "\(formatted(state.value))/\(formatted(state.goal)) \(state.unit.displayName)"
    }

    private func formatted(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
    }
}

private struct DoseCompletionRing: View {
    let state: InputDoseState
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(TelocareTheme.peach, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: state.completionClamped)
                .stroke(
                    state.isGoalMet ? TelocareTheme.success : TelocareTheme.coral,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((state.completionRaw * 100).rounded()))%")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(TelocareTheme.charcoal)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Weekly Progress Bar

private struct WeeklyProgressBar: View {
    let completion: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < Int(completion * 7) ? TelocareTheme.coral : TelocareTheme.peach)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Evidence Badge

private struct EvidenceBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(TelocareTheme.Typography.small)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch level.lowercased() {
        case "strong", "high":
            return TelocareTheme.success
        case "moderate", "medium":
            return TelocareTheme.warmOrange
        default:
            return TelocareTheme.muted
        }
    }
}

private struct InputDetailView: View {
    let input: InputStatus
    let graphData: CausalGraphData
    let onIncrementDose: (String) -> Void
    let onDecrementDose: (String) -> Void
    let onResetDose: (String) -> Void
    let onUpdateDoseSettings: (String, Double, Double) -> Void
    let onConnectAppleHealth: (String) -> Void
    let onDisconnectAppleHealth: (String) -> Void
    let onRefreshAppleHealth: (String) async -> Void
    let onToggleActive: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dailyGoalText: String = ""
    @State private var incrementText: String = ""
    @State private var liveDoseState: InputDoseState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                Text(input.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)

                appleHealthCard
                statusCard
                InputCompletionHistoryCard(events: input.completionEvents)
                doseCard
                evidenceCard

                if input.detailedDescription != nil {
                    descriptionCard
                }

                if input.externalLink != nil {
                    linkCard
                }

                trackingCard
            }
            .padding(TelocareTheme.Spacing.md)
        }
        .background(TelocareTheme.sand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let doseState = input.doseState {
                liveDoseState = doseState
                dailyGoalText = formattedDoseValue(doseState.goal)
                incrementText = formattedDoseValue(doseState.increment)
            }
        }
        .onChange(of: input.doseState) { _, updatedDoseState in
            liveDoseState = updatedDoseState
        }
    }

    // MARK: - Tracking Card

    @ViewBuilder
    private var trackingCard: some View {
        WarmCard {
            Button {
                onToggleActive(input.id)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: input.isActive ? "minus.circle" : "plus.circle")
                        .font(.system(size: 16))
                    Text(input.isActive ? "Stop tracking this intervention" : "Start tracking this intervention")
                        .font(TelocareTheme.Typography.body)
                    Spacer()
                }
                .foregroundStyle(input.isActive ? TelocareTheme.warmGray : TelocareTheme.coral)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Dose Card

    @ViewBuilder
    private var appleHealthCard: some View {
        if input.trackingMode == .dose, let appleHealthState = input.appleHealthState, appleHealthState.available {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Apple Health")

                    if appleHealthState.connected {
                        DetailRow(label: "Connection", value: "Connected")
                        DetailRow(label: "Sync status", value: appleHealthStatusText(appleHealthState.syncStatus))

                        if let healthValue = appleHealthState.todayHealthValue, let doseState = currentDoseState {
                            DetailRow(
                                label: "Today in Apple Health",
                                value: "\(formattedDoseValue(healthValue)) \(doseState.unit.displayName)"
                            )
                        } else {
                            Text("No Apple Health data found today. Using app dose entries.")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                        }

                        if let lastSyncAt = appleHealthState.lastSyncAt {
                            DetailRow(label: "Last sync", value: lastSyncAt)
                        }

                        HStack(spacing: TelocareTheme.Spacing.sm) {
                            Button("Refresh Apple Health") {
                                Task {
                                    await onRefreshAppleHealth(input.id)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(TelocareTheme.coral)
                            .accessibilityIdentifier(AccessibilityID.exploreInputAppleHealthRefresh)
                            .accessibilityHint("Refreshes today's Apple Health value for this intervention.")

                            Button("Disconnect") {
                                onDisconnectAppleHealth(input.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(TelocareTheme.warmGray)
                            .accessibilityIdentifier(AccessibilityID.exploreInputAppleHealthDisconnect)
                            .accessibilityHint("Stops Apple Health sync for this intervention.")
                        }
                    } else {
                        Text("Connect to Apple Health to read today's value automatically.")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)

                        Button("Connect to Apple Health") {
                            onConnectAppleHealth(input.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TelocareTheme.coral)
                        .accessibilityIdentifier(AccessibilityID.exploreInputAppleHealthConnect)
                        .accessibilityHint("Requests read access for this intervention's Apple Health data.")
                    }
                }
            }
        }
    }

    private func appleHealthStatusText(_ status: AppleHealthSyncStatus) -> String {
        switch status {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .noData:
            return "No data today"
        case .failed:
            return "Sync failed"
        }
    }

    @ViewBuilder
    private var doseCard: some View {
        if input.trackingMode == .dose, let doseState = currentDoseState {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Dose Tracking")

                    HStack(spacing: TelocareTheme.Spacing.md) {
                        DoseCompletionRing(state: doseState, size: 60, lineWidth: 6)
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text("Today")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                            Text("\(formattedDoseValue(doseState.value)) / \(formattedDoseValue(doseState.goal)) \(doseState.unit.displayName)")
                                .font(TelocareTheme.Typography.body)
                                .foregroundStyle(TelocareTheme.charcoal)
                            Text("Increment: \(formattedDoseValue(doseState.increment)) \(doseState.unit.displayName)")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                        }
                        Spacer()
                    }

                    HStack(spacing: TelocareTheme.Spacing.sm) {
                        doseActionButton(
                            title: "−",
                            systemImage: "minus.circle.fill",
                            accessibilityID: AccessibilityID.exploreInputDoseDecrement
                        ) {
                            applyLocalDoseDelta(-doseState.increment)
                            onDecrementDose(input.id)
                        }
                        doseActionButton(
                            title: "+",
                            systemImage: "plus.circle.fill",
                            accessibilityID: AccessibilityID.exploreInputDoseIncrement
                        ) {
                            applyLocalDoseDelta(doseState.increment)
                            onIncrementDose(input.id)
                        }
                        doseActionButton(
                            title: "Reset",
                            systemImage: "arrow.counterclockwise.circle.fill",
                            accessibilityID: AccessibilityID.exploreInputDoseReset
                        ) {
                            applyLocalDoseReset()
                            onResetDose(input.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                        Text("Daily Goal and Increment")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)

                        HStack(spacing: TelocareTheme.Spacing.sm) {
                            TextField("Goal", text: $dailyGoalText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Daily goal")

                            TextField("Increment", text: $incrementText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Dose increment")
                        }

                        Button("Save Dose Settings") {
                            saveDoseSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TelocareTheme.coral)
                        .accessibilityIdentifier(AccessibilityID.exploreInputDoseSaveSettings)
                        .accessibilityHint("Saves this intervention goal and increment.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func doseActionButton(
        title: String,
        systemImage: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(TelocareTheme.Typography.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(TelocareTheme.coral)
        .accessibilityIdentifier(accessibilityID)
    }

    private func saveDoseSettings() {
        guard let goal = parsePositiveNumber(dailyGoalText), let increment = parsePositiveNumber(incrementText) else {
            return
        }

        if let doseState = currentDoseState {
            liveDoseState = InputDoseState(
                manualValue: doseState.manualValue,
                healthValue: doseState.healthValue,
                goal: goal,
                increment: increment,
                unit: doseState.unit
            )
        }

        onUpdateDoseSettings(input.id, goal, increment)
    }

    private var currentDoseState: InputDoseState? {
        liveDoseState ?? input.doseState
    }

    private func applyLocalDoseDelta(_ delta: Double) {
        guard let doseState = currentDoseState else {
            return
        }

        let nextManualValue = max(0, doseState.manualValue + delta)
        liveDoseState = InputDoseState(
            manualValue: nextManualValue,
            healthValue: doseState.healthValue,
            goal: doseState.goal,
            increment: doseState.increment,
            unit: doseState.unit
        )
    }

    private func applyLocalDoseReset() {
        guard let doseState = currentDoseState else {
            return
        }

        liveDoseState = InputDoseState(
            manualValue: 0,
            healthValue: doseState.healthValue,
            goal: doseState.goal,
            increment: doseState.increment,
            unit: doseState.unit
        )
    }

    private func parsePositiveNumber(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }

        return value
    }

    private func formattedDoseValue(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
    }

    private var currentStatusText: String {
        guard input.trackingMode == .dose, let doseState = currentDoseState else {
            return input.statusText
        }

        let completionPercent = Int((doseState.completionRaw * 100).rounded())
        return "\(formattedDoseValue(doseState.value)) of \(formattedDoseValue(doseState.goal)) \(doseState.unit.displayName) (\(completionPercent)%)"
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Status")

                DetailRow(label: "Tracking", value: input.isActive ? "Active" : "Available")
                DetailRow(label: "Status", value: currentStatusText)
                if input.trackingMode == .binary {
                    DetailRow(label: "7-day completion", value: "\(Int((input.completion * 100).rounded()))%")
                    DetailRow(label: "Checked today", value: input.isCheckedToday ? "Yes" : "No")
                } else if let doseState = currentDoseState {
                    DetailRow(label: "Goal reached", value: doseState.isGoalMet ? "Yes" : "No")
                    DetailRow(label: "Current dose", value: "\(formattedDoseValue(doseState.value)) \(doseState.unit.displayName)")
                    DetailRow(label: "Daily goal", value: "\(formattedDoseValue(doseState.goal)) \(doseState.unit.displayName)")
                }

                if let classification = input.classificationText {
                    DetailRow(label: "Classification", value: classification)
                }
            }
        }
    }

    // MARK: - Evidence Card

    @ViewBuilder
    private var evidenceCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Evidence")

                if let level = input.evidenceLevel ?? graphNodeData?.tooltip?.evidence {
                    HStack {
                        Text("Level")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                        Spacer()
                        EvidenceBadge(level: level)
                    }
                }

                if let summary = input.evidenceSummary ?? graphNodeData?.tooltip?.mechanism {
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Text("Summary")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                        Text(summary)
                            .font(TelocareTheme.Typography.body)
                            .foregroundStyle(TelocareTheme.charcoal)
                    }
                }

                if !input.citationIDs.isEmpty {
                    DetailRow(label: "Citations", value: input.citationIDs.joined(separator: ", "))
                }

                if let stat = graphNodeData?.tooltip?.stat {
                    DetailRow(label: "Statistic", value: stat)
                }
            }
        }
    }

    // MARK: - Description Card

    @ViewBuilder
    private var descriptionCard: some View {
        if let description = input.detailedDescription {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Description")
                    Text(description)
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.charcoal)
                }
            }
        }
    }

    // MARK: - Link Card

    @ViewBuilder
    private var linkCard: some View {
        if let link = input.externalLink {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Reference")
                    if let url = URL(string: link) {
                        Link(destination: url) {
                            HStack {
                                Text(link)
                                    .font(TelocareTheme.Typography.body)
                                    .foregroundStyle(TelocareTheme.coral)
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(TelocareTheme.coral)
                            }
                        }
                    } else {
                        Text(link)
                            .font(TelocareTheme.Typography.body)
                            .foregroundStyle(TelocareTheme.charcoal)
                    }
                }
            }
        }
    }

    private var graphNodeData: GraphNodeData? {
        let nodeID = input.graphNodeID ?? input.id
        return graphData.nodes.first { $0.data.id == nodeID }?.data
    }
}

// MARK: - Detail Row Helper

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
            Spacer()
            Text(value)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.charcoal)
        }
    }
}

private struct ExploreChatScreen: View {
    @Binding var draft: String
    let feedback: String
    let onSend: () -> Void
    let selectedSkinID: TelocareSkinID

    @State private var messages: [ChatMessage] = [
        ChatMessage(
            id: UUID(),
            content: "Hi there! I'm your sleep wellness assistant. I can help you understand your sleep patterns, suggest interventions, and answer questions about TMD management. What would you like to explore today?",
            isFromUser: false,
            timestamp: Date()
        )
    ]
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: TelocareTheme.Spacing.md) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(TelocareTheme.Spacing.md)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }

                if messages.count <= 2 {
                    suggestedPromptsSection
                }

                chatInputBar
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
    }

    // MARK: - Suggested Prompts

    @ViewBuilder
    private var suggestedPromptsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button {
                        sendMessage(prompt)
                    } label: {
                        Text(prompt)
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.coral)
                            .padding(.horizontal, TelocareTheme.Spacing.md)
                            .padding(.vertical, TelocareTheme.Spacing.sm)
                            .background(TelocareTheme.peach)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.bottom, TelocareTheme.Spacing.sm)
        }
    }

    private var suggestedPrompts: [String] {
        [
            "Why is my jaw sore?",
            "What can I try tonight?",
            "Explain my progress",
            "Best interventions for me"
        ]
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(TelocareTheme.peach)

            HStack(spacing: TelocareTheme.Spacing.sm) {
                TextField("Ask anything about your sleep...", text: $draft, axis: .vertical)
                    .font(TelocareTheme.Typography.body)
                    .padding(.horizontal, TelocareTheme.Spacing.md)
                    .padding(.vertical, TelocareTheme.Spacing.sm)
                    .background(TelocareTheme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous))
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .accessibilityIdentifier(AccessibilityID.exploreChatInput)

                Button {
                    sendMessage(draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(draft.isEmpty ? TelocareTheme.muted : TelocareTheme.coral)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(AccessibilityID.exploreChatSendButton)
            }
            .padding(TelocareTheme.Spacing.md)
            .background(TelocareTheme.sand)
        }
    }

    private func sendMessage(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(id: UUID(), content: trimmed, isFromUser: true, timestamp: Date()))
        draft = ""
        onSend()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            messages.append(ChatMessage(
                id: UUID(),
                content: "I appreciate your question! The AI backend isn't connected yet, but once it is, I'll be able to help analyze your sleep data and provide personalized recommendations.",
                isFromUser: false,
                timestamp: Date()
            ))
        }
    }
}

// MARK: - Chat Message Model

private struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 60) }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: TelocareTheme.Spacing.xs) {
                Text(message.content)
                    .font(TelocareTheme.Typography.body)
                    .foregroundStyle(message.isFromUser ? .white : TelocareTheme.charcoal)
                    .padding(TelocareTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous)
                            .fill(message.isFromUser ? TelocareTheme.coral : TelocareTheme.cream)
                    )

                Text(formattedTime)
                    .font(TelocareTheme.Typography.small)
                    .foregroundStyle(TelocareTheme.muted)
            }

            if !message.isFromUser { Spacer(minLength: 60) }
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
