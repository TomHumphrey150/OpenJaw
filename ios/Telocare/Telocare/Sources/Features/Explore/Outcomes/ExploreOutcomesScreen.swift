import Charts
import SwiftUI

struct ExploreOutcomesScreen: View {
    let outcomes: OutcomeSummary
    let outcomeRecords: [OutcomeRecord]
    let outcomesMetadata: OutcomesMetadata
    let chartMorningStates: [MorningState]
    let chartNightOutcomes: [NightOutcome]
    let chartExclusionNote: String?
    let foundationCheckInNightID: String
    let foundationQuestions: [GraphDerivedProgressQuestion]
    let foundationResponsesByQuestionID: [String: Int]
    let foundationRequiredQuestionIDs: [String]
    let morningTrendMetrics: [MorningTrendMetric]
    let museConnectionStatusText: String
    let museRecordingStatusText: String
    let museSessionFeedback: String
    let museDisclaimerText: String
    let museCanScan: Bool
    let museCanConnect: Bool
    let museCanDisconnect: Bool
    let museCanStartRecording: Bool
    let museCanStopRecording: Bool
    let museIsRecording: Bool
    let museCanSaveNightOutcome: Bool
    let museRecordingSummary: MuseRecordingSummary?
    let museLiveDiagnostics: MuseLiveDiagnostics?
    let museSetupDiagnosticsFileURLs: [URL]
    let isMuseFitCalibrationPresented: Bool
    let museFitDiagnostics: MuseLiveDiagnostics?
    let museFitPrimaryBlockerText: String?
    let museFitReadyStreakSeconds: Int
    let museFitReadyRequiredSeconds: Int
    let museCanStartRecordingFromFitCalibration: Bool
    let museCanStartRecordingWithFitOverride: Bool
    let onSetFoundationCheckInValue: (Int?, String) -> Void
    let onScanForMuse: () -> Void
    let onConnectToMuse: () -> Void
    let onDisconnectMuse: () -> Void
    let onStartMuseRecording: () -> Void
    let onDismissMuseFitCalibration: () -> Void
    let onStartMuseRecordingFromFitCalibration: () -> Void
    let onStartMuseRecordingWithFitOverride: () -> Void
    let onExportMuseSetupDiagnosticsSnapshot: () async -> [URL]
    let onStopMuseRecording: () -> Void
    let onSaveMuseNightOutcome: () -> Void
    let isMuseSessionEnabled: Bool
    let flareSuggestion: FlareSuggestion?
    let onAcceptFlareSuggestion: () -> Void
    let onDismissFlareSuggestion: () -> Void
    let selectedSkinID: TelocareSkinID

    @State private var navigationPath = NavigationPath()
    @State private var isFoundationCheckInExpanded: Bool
    @State private var selectedMorningMetric: MorningTrendMetric
    @State private var selectedNightMetric: NightTrendMetric
    @State private var isMuseDiagnosticsSharePresented = false
    @State private var museDiagnosticsShareURLs: [URL] = []
    @State private var museDiagnosticsExportFeedback: String?

    init(
        outcomes: OutcomeSummary,
        outcomeRecords: [OutcomeRecord],
        outcomesMetadata: OutcomesMetadata,
        chartMorningStates: [MorningState],
        chartNightOutcomes: [NightOutcome],
        chartExclusionNote: String?,
        foundationCheckInNightID: String,
        foundationQuestions: [GraphDerivedProgressQuestion],
        foundationResponsesByQuestionID: [String: Int],
        foundationRequiredQuestionIDs: [String],
        morningTrendMetrics: [MorningTrendMetric],
        museConnectionStatusText: String,
        museRecordingStatusText: String,
        museSessionFeedback: String,
        museDisclaimerText: String,
        museCanScan: Bool,
        museCanConnect: Bool,
        museCanDisconnect: Bool,
        museCanStartRecording: Bool,
        museCanStopRecording: Bool,
        museIsRecording: Bool,
        museCanSaveNightOutcome: Bool,
        museRecordingSummary: MuseRecordingSummary?,
        museLiveDiagnostics: MuseLiveDiagnostics?,
        museSetupDiagnosticsFileURLs: [URL],
        isMuseFitCalibrationPresented: Bool,
        museFitDiagnostics: MuseLiveDiagnostics?,
        museFitPrimaryBlockerText: String?,
        museFitReadyStreakSeconds: Int,
        museFitReadyRequiredSeconds: Int,
        museCanStartRecordingFromFitCalibration: Bool,
        museCanStartRecordingWithFitOverride: Bool,
        onSetFoundationCheckInValue: @escaping (Int?, String) -> Void,
        onScanForMuse: @escaping () -> Void,
        onConnectToMuse: @escaping () -> Void,
        onDisconnectMuse: @escaping () -> Void,
        onStartMuseRecording: @escaping () -> Void,
        onDismissMuseFitCalibration: @escaping () -> Void,
        onStartMuseRecordingFromFitCalibration: @escaping () -> Void,
        onStartMuseRecordingWithFitOverride: @escaping () -> Void,
        onExportMuseSetupDiagnosticsSnapshot: @escaping () async -> [URL],
        onStopMuseRecording: @escaping () -> Void,
        onSaveMuseNightOutcome: @escaping () -> Void,
        isMuseSessionEnabled: Bool,
        flareSuggestion: FlareSuggestion?,
        onAcceptFlareSuggestion: @escaping () -> Void,
        onDismissFlareSuggestion: @escaping () -> Void,
        selectedSkinID: TelocareSkinID
    ) {
        self.outcomes = outcomes
        self.outcomeRecords = outcomeRecords
        self.outcomesMetadata = outcomesMetadata
        self.chartMorningStates = chartMorningStates
        self.chartNightOutcomes = chartNightOutcomes
        self.chartExclusionNote = chartExclusionNote
        self.foundationCheckInNightID = foundationCheckInNightID
        self.foundationQuestions = foundationQuestions
        self.foundationResponsesByQuestionID = foundationResponsesByQuestionID
        self.foundationRequiredQuestionIDs = foundationRequiredQuestionIDs
        self.morningTrendMetrics = morningTrendMetrics
        self.museConnectionStatusText = museConnectionStatusText
        self.museRecordingStatusText = museRecordingStatusText
        self.museSessionFeedback = museSessionFeedback
        self.museDisclaimerText = museDisclaimerText
        self.museCanScan = museCanScan
        self.museCanConnect = museCanConnect
        self.museCanDisconnect = museCanDisconnect
        self.museCanStartRecording = museCanStartRecording
        self.museCanStopRecording = museCanStopRecording
        self.museIsRecording = museIsRecording
        self.museCanSaveNightOutcome = museCanSaveNightOutcome
        self.museRecordingSummary = museRecordingSummary
        self.museLiveDiagnostics = museLiveDiagnostics
        self.museSetupDiagnosticsFileURLs = museSetupDiagnosticsFileURLs
        self.isMuseFitCalibrationPresented = isMuseFitCalibrationPresented
        self.museFitDiagnostics = museFitDiagnostics
        self.museFitPrimaryBlockerText = museFitPrimaryBlockerText
        self.museFitReadyStreakSeconds = museFitReadyStreakSeconds
        self.museFitReadyRequiredSeconds = museFitReadyRequiredSeconds
        self.museCanStartRecordingFromFitCalibration = museCanStartRecordingFromFitCalibration
        self.museCanStartRecordingWithFitOverride = museCanStartRecordingWithFitOverride
        self.onSetFoundationCheckInValue = onSetFoundationCheckInValue
        self.onScanForMuse = onScanForMuse
        self.onConnectToMuse = onConnectToMuse
        self.onDisconnectMuse = onDisconnectMuse
        self.onStartMuseRecording = onStartMuseRecording
        self.onDismissMuseFitCalibration = onDismissMuseFitCalibration
        self.onStartMuseRecordingFromFitCalibration = onStartMuseRecordingFromFitCalibration
        self.onStartMuseRecordingWithFitOverride = onStartMuseRecordingWithFitOverride
        self.onExportMuseSetupDiagnosticsSnapshot = onExportMuseSetupDiagnosticsSnapshot
        self.onStopMuseRecording = onStopMuseRecording
        self.onSaveMuseNightOutcome = onSaveMuseNightOutcome
        self.isMuseSessionEnabled = isMuseSessionEnabled
        self.flareSuggestion = flareSuggestion
        self.onAcceptFlareSuggestion = onAcceptFlareSuggestion
        self.onDismissFlareSuggestion = onDismissFlareSuggestion
        self.selectedSkinID = selectedSkinID
        _isFoundationCheckInExpanded = State(
            initialValue: !Self.isFoundationCheckInComplete(
                responsesByQuestionID: foundationResponsesByQuestionID,
                requiredQuestionIDs: foundationRequiredQuestionIDs
            )
        )
        _selectedMorningMetric = State(initialValue: morningTrendMetrics.first ?? .composite)
        _selectedNightMetric = State(initialValue: .microArousalRatePerHour)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: TelocareTheme.Spacing.lg) {
                    flareSuggestionSection
                    morningGreetingCard
                    foundationCheckInSection
                    morningTrendSection
                    measurementRoadmapSection
                    if isMuseSessionEnabled {
                        museSessionSection
                    }
                }
                .padding(.horizontal, TelocareTheme.Spacing.md)
                .padding(.vertical, TelocareTheme.Spacing.lg)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: OutcomeRecord.self) { record in
                OutcomeDetailView(record: record, outcomesMetadata: outcomesMetadata)
                    .accessibilityIdentifier(AccessibilityID.exploreOutcomeDetailSheet)
            }
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
        .sheet(isPresented: $isMuseDiagnosticsSharePresented) {
            MuseDiagnosticsShareSheet(fileURLs: museDiagnosticsShareURLs)
        }
        .fullScreenCover(isPresented: museFitCalibrationBinding) {
            MuseFitCalibrationSheet(
                diagnostics: museFitDiagnostics,
                readyStreakSeconds: museFitReadyStreakSeconds,
                requiredReadySeconds: museFitReadyRequiredSeconds,
                primaryBlockerText: museFitPrimaryBlockerText,
                canStartWhenReady: museCanStartRecordingFromFitCalibration,
                canStartWithOverride: museCanStartRecordingWithFitOverride,
                canExportSetupDiagnostics: isMuseFitCalibrationPresented || !museSetupDiagnosticsFileURLs.isEmpty,
                onClose: onDismissMuseFitCalibration,
                onStartWhenReady: onStartMuseRecordingFromFitCalibration,
                onStartWithOverride: onStartMuseRecordingWithFitOverride,
                onExportSetupDiagnostics: exportMuseSetupDiagnostics
            )
        }
        .onChange(of: foundationResponsesByQuestionID) { _, responses in
            let isComplete = Self.isFoundationCheckInComplete(
                responsesByQuestionID: responses,
                requiredQuestionIDs: foundationRequiredQuestionIDs
            )
            guard isComplete else { return }
            guard isFoundationCheckInExpanded else { return }
            withAnimation(.spring(response: 0.3)) {
                isFoundationCheckInExpanded = false
            }
        }
    }

    @ViewBuilder
    private var flareSuggestionSection: some View {
        if let flareSuggestion {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    Text(flareSuggestion.direction == .enterFlare ? "Possible flare detected" : "Flare may be resolving")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)
                    Text(flareSuggestion.reason)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)

                    HStack(spacing: TelocareTheme.Spacing.sm) {
                        Button("Apply") {
                            onAcceptFlareSuggestion()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.exploreOutcomesFlareAccept)

                        Button("Dismiss", role: .cancel) {
                            onDismissFlareSuggestion()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(AccessibilityID.exploreOutcomesFlareDismiss)
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.exploreOutcomesFlareSuggestion)
        }
    }

    private func showRecordDetail(_ record: OutcomeRecord) {
        navigationPath.append(record)
    }

    private var museFitCalibrationBinding: Binding<Bool> {
        Binding(
            get: { isMuseSessionEnabled && isMuseFitCalibrationPresented },
            set: { isPresented in
                if !isPresented {
                    onDismissMuseFitCalibration()
                }
            }
        )
    }

    // MARK: - Morning Greeting Card

    @ViewBuilder
    private var morningGreetingCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                Text(greetingText)
                    .font(TelocareTheme.Typography.largeTitle)
                    .foregroundStyle(TelocareTheme.charcoal)
                Text(greetingPrompt)
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

    private var greetingPrompt: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "How are you feeling this morning?"
        case 12..<17:
            return "How are you feeling?"
        default:
            return "Checking in on your day."
        }
    }

    @ViewBuilder
    private var foundationCheckInSection: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isFoundationCheckInExpanded.toggle()
                }
            } label: {
                HStack {
                    WarmSectionHeader(
                        title: "Pillar check-in",
                        subtitle: "Night \(foundationCheckInNightID) • Required daily"
                    )
                    Spacer()
                    Image(systemName: isFoundationCheckInExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(TelocareTheme.warmGray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.exploreOutcomesFoundationCheckInToggle)
            .accessibilityValue(isFoundationCheckInExpanded ? "Expanded" : "Collapsed")

            if isFoundationCheckInExpanded {
                VStack(spacing: TelocareTheme.Spacing.md) {
                    ForEach(foundationQuestions, id: \.id) { question in
                        FoundationEmojiRatingPicker(
                            questionID: question.id,
                            title: question.title,
                            value: Binding(
                                get: { foundationResponsesByQuestionID[question.id] },
                                set: { onSetFoundationCheckInValue($0, question.id) }
                            )
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private static func isFoundationCheckInComplete(
        responsesByQuestionID: [String: Int],
        requiredQuestionIDs: [String]
    ) -> Bool {
        !requiredQuestionIDs.contains { responsesByQuestionID[$0] == nil }
    }

    private var morningTrendPoints: [OutcomeTrendPoint] {
        OutcomeTrendDataBuilder()
            .morningPoints(
                from: chartMorningStates,
                metric: selectedMorningMetric,
                compositeComponents: morningTrendMetrics.filter { $0 != .composite }
            )
    }

    private var nightTrendPoints: [OutcomeTrendPoint] {
        OutcomeTrendDataBuilder()
            .nightPoints(from: chartNightOutcomes, metric: selectedNightMetric)
    }

    private var morningChartHeight: CGFloat {
        280
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
        guard let latest = morningTrendPoints.last else {
            return "\(selectedMorningMetric.title), no data, lower is better"
        }

        return "\(selectedMorningMetric.title), \(formattedMorningValue(latest.value)), \(morningEmoji(for: latest.value)), lower is better"
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
                        ForEach(morningTrendMetrics) { metric in
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
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.15))
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
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.15))
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

                if let chartExclusionNote, !chartExclusionNote.isEmpty {
                    Text(chartExclusionNote)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
    private var measurementRoadmapSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                WarmSectionHeader(
                    title: "Measurement roadmap",
                    subtitle: "Planned evidence bundles"
                )

                Text("Daily: steps, sleep regularity, hydration, mood check-in.")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Weekly: exercise completion, social count, stress check, alcohol-free days.")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Monthly and quarterly: PSQI, PHQ-9, GAD-7, PSS-10, MEDAS, loneliness, financial distress.")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Biannual and annual: labs, dental, VO2max, lipid and inflammation markers, preventive screening.")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.exploreOutcomesMeasurementRoadmap)
        .accessibilityLabel("Measurement roadmap")
        .accessibilityValue(
            "Daily metrics, weekly adherence, monthly and quarterly questionnaires, and annual preventive markers."
        )
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
                        .accessibilityIdentifier(AccessibilityID.exploreMuseSummaryText)
                }

                if let reliabilityText = museRecordingReliabilityText {
                    Text(reliabilityText)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseReliabilityText)
                }

                if let liveStatusText = museLiveStatusText {
                    Text(liveStatusText)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseLiveStatusText)
                }

                if let fitGuidanceText = museFitGuidanceText {
                    Text(fitGuidanceText)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseFitGuidanceText)
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
                    actionButton(
                        title: "Export setup diagnostics (full zip)",
                        accessibilityID: AccessibilityID.exploreMuseExportSetupDiagnosticsButton,
                        isEnabled: museCanExportSetupDiagnostics,
                        action: exportMuseSetupDiagnostics
                    )
                    actionButton(
                        title: "Export diagnostics (full zip)",
                        accessibilityID: AccessibilityID.exploreMuseExportDiagnosticsButton,
                        isEnabled: museCanExportDiagnostics,
                        action: exportMuseDiagnostics
                    )
                }

                if let museDiagnosticsExportFeedback {
                    Text(museDiagnosticsExportFeedback)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.exploreMuseExportFeedbackText)
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

        let confidenceText = String(format: "%.2f", summary.confidence)
        let awakeLikelihoodText = String(format: "%.2f", summary.awakeLikelihood)
        return "Microarousals \(Int(summary.microArousalCount.rounded())), rate \(rateText), signal confidence \(confidenceText), awake likelihood (provisional) \(awakeLikelihoodText)."
    }

    private var museLiveStatusText: String? {
        if let diagnostics = museLiveDiagnostics {
            let streamStatus: String
            if diagnostics.isReceivingData {
                streamStatus = "receiving live packets"
            } else {
                streamStatus = "not receiving recent packets"
            }

            let packetTimingText: String
            if let lastPacketAgeSeconds = diagnostics.lastPacketAgeSeconds {
                packetTimingText = String(format: "%.1fs ago", lastPacketAgeSeconds)
            } else {
                packetTimingText = "never"
            }

            let confidenceText = String(format: "%.2f", diagnostics.signalConfidence)
            let awakeLikelihoodText = String(format: "%.2f", diagnostics.awakeLikelihood)
            let headbandCoverageText = String(format: "%.2f", diagnostics.headbandOnCoverage)
            let qualityCoverageText = String(format: "%.2f", diagnostics.qualityGateCoverage)
            let droppedTypeText = droppedPacketTypeText(diagnostics.droppedPacketTypes)

            return "Live status: \(streamStatus), last packet \(packetTimingText), elapsed \(diagnostics.elapsedSeconds)s. Parsed \(diagnostics.parsedPacketCount) packets from \(diagnostics.rawDataPacketCount) data and \(diagnostics.rawArtifactPacketCount) artifact packets. Dropped \(diagnostics.droppedPacketCount) packets (\(droppedTypeText)). Signal confidence \(confidenceText), awake likelihood (provisional) \(awakeLikelihoodText), headband-on coverage \(headbandCoverageText), quality-gate coverage \(qualityCoverageText)."
        }

        guard museIsRecording else {
            return nil
        }

        return "Live status: waiting for packet telemetry. Keep the phone near the headband and adjust fit if this persists."
    }

    private var museFitGuidanceText: String? {
        if let guidanceText = museLiveDiagnostics?.fitGuidance.guidanceText {
            return guidanceText
        }

        return museRecordingSummary?.fitGuidance.guidanceText
    }

    private var museRecordingReliabilityText: String? {
        guard let summary = museRecordingSummary else {
            return nil
        }

        let baseText = "Recording reliability: \(summary.recordingReliability.displayText)."
        if summary.startedWithFitOverride {
            return "\(baseText) Started with fit override."
        }

        return baseText
    }

    private var museCanExportDiagnostics: Bool {
        guard let summary = museRecordingSummary else {
            return false
        }

        return !summary.diagnosticsFileURLs.isEmpty
    }

    private var museCanExportSetupDiagnostics: Bool {
        !museSetupDiagnosticsFileURLs.isEmpty
    }

    private func exportMuseDiagnostics() {
        guard let summary = museRecordingSummary else {
            return
        }
        guard !summary.diagnosticsFileURLs.isEmpty else {
            return
        }

        do {
            let exportArchiveURL = try MuseDiagnosticsExportBundle.make(fileURLs: summary.diagnosticsFileURLs)
            MuseDiagnosticsLogger.info("Prepared diagnostics export archive at \(exportArchiveURL.path)")
            museDiagnosticsExportFeedback = "Prepared full diagnostics zip archive for sharing."
            museDiagnosticsShareURLs = [exportArchiveURL]
            isMuseDiagnosticsSharePresented = true
        } catch {
            MuseDiagnosticsLogger.error("Diagnostics export failed: \(error.localizedDescription)")
            museDiagnosticsExportFeedback = "Could not prepare diagnostics files for sharing."
        }
    }

    private func exportMuseSetupDiagnostics() {
        Task {
            let setupDiagnosticsFileURLs = await onExportMuseSetupDiagnosticsSnapshot()
            if setupDiagnosticsFileURLs.isEmpty {
                MuseDiagnosticsLogger.warn("Setup diagnostics export requested but no files were available")
                museDiagnosticsExportFeedback = "No setup diagnostics files are available yet."
                return
            }

            do {
                let archiveURL = try MuseDiagnosticsExportBundle.make(
                    fileURLs: setupDiagnosticsFileURLs,
                    capturePhase: .setup
                )
                MuseDiagnosticsLogger.info("Prepared setup diagnostics export archive at \(archiveURL.path)")
                museDiagnosticsExportFeedback = "Prepared setup diagnostics zip archive for sharing."
                museDiagnosticsShareURLs = [archiveURL]
                isMuseDiagnosticsSharePresented = true
            } catch {
                MuseDiagnosticsLogger.error("Setup diagnostics export failed: \(error.localizedDescription)")
                museDiagnosticsExportFeedback = "Could not prepare setup diagnostics files for sharing."
            }
        }
    }

    private func droppedPacketTypeText(_ droppedPacketTypes: [MuseDroppedPacketTypeCount]) -> String {
        if droppedPacketTypes.isEmpty {
            return "none"
        }

        return droppedPacketTypes
            .map { "\($0.label) (\($0.code)): \($0.count)" }
            .joined(separator: ", ")
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

private struct FoundationEmojiRatingPicker: View {
    let questionID: String
    let title: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(TelocareTheme.coral)
                Text(title)
                    .font(TelocareTheme.Typography.headline)
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let value {
                    Text("\(FoundationCheckInScale.emoji(for: value)) \(value)")
                        .font(TelocareTheme.Typography.small)
                        .foregroundStyle(TelocareTheme.coral)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TelocareTheme.peach)
                        .clipShape(Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TelocareTheme.Spacing.xs) {
                    ForEach(FoundationCheckInScale.options, id: \.self) { option in
                        Button {
                            value = option
                        } label: {
                            VStack(spacing: 4) {
                                Text(FoundationCheckInScale.emoji(for: option))
                                    .font(.system(size: 20, weight: .regular, design: .rounded))
                                Text("\(option)")
                                    .font(TelocareTheme.Typography.small)
                                    .foregroundStyle(value == option ? TelocareTheme.coral : TelocareTheme.warmGray)
                            }
                            .frame(width: 38, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                                    .fill(value == option ? TelocareTheme.peach : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                                    .stroke(
                                        value == option ? TelocareTheme.coral : TelocareTheme.muted.opacity(0.3),
                                        lineWidth: value == option ? 2 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) \(option)")
                        .accessibilityAddTraits(value == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(TelocareTheme.Spacing.md)
        .background(TelocareTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.exploreOutcomesFoundationQuestion(questionID: questionID))
    }
}
