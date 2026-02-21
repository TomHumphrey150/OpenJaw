import SwiftUI

struct ExploreTabShell: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView(selection: selectedTabBinding) {
            ExploreInputsScreen(
                inputs: viewModel.snapshot.inputs,
                graphData: viewModel.graphData,
                onToggleCheckedToday: viewModel.toggleInputCheckedToday
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
                onShowProtectiveEdgesChanged: viewModel.setShowProtectiveEdges
            )
            .tabItem { Label(ExploreTab.situation.title, systemImage: ExploreTab.situation.symbolName) }
            .tag(ExploreTab.situation)
            .accessibilityIdentifier(AccessibilityID.exploreSituationScreen)

            ExploreOutcomesScreen(
                outcomes: viewModel.snapshot.outcomes,
                outcomeRecords: viewModel.snapshot.outcomeRecords,
                outcomesMetadata: viewModel.snapshot.outcomesMetadata,
                morningOutcomeSelection: viewModel.morningOutcomeSelection,
                onSetMorningOutcomeValue: viewModel.setMorningOutcomeValue,
                onSaveMorningOutcomes: viewModel.saveMorningOutcomes
            )
                .tabItem { Label(ExploreTab.outcomes.title, systemImage: ExploreTab.outcomes.symbolName) }
                .tag(ExploreTab.outcomes)
                .accessibilityIdentifier(AccessibilityID.exploreOutcomesScreen)

            ExploreChatScreen(
                draft: $viewModel.chatDraft,
                feedback: viewModel.exploreFeedback,
                onSend: viewModel.submitChatPrompt
            )
                .tabItem { Label(ExploreTab.chat.title, systemImage: ExploreTab.chat.symbolName) }
                .tag(ExploreTab.chat)
                .accessibilityIdentifier(AccessibilityID.exploreChatScreen)
        }
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
    let morningOutcomeSelection: MorningOutcomeSelection
    let onSetMorningOutcomeValue: (Int?, MorningOutcomeField) -> Void
    let onSaveMorningOutcomes: () -> Void

    @State private var navigationPath = NavigationPath()
    @State private var isMorningCheckInExpanded = true

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: TelocareTheme.Spacing.lg) {
                    morningGreetingCard
                    morningCheckInSection
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
            }
            .buttonStyle(.plain)

            if isMorningCheckInExpanded {
                VStack(spacing: TelocareTheme.Spacing.md) {
                    ForEach(MorningOutcomeField.allCases) { field in
                        EmojiRatingPicker(
                            field: field,
                            value: bindingForField(field)
                        )
                        .accessibilityIdentifier(field.accessibilityIdentifier)
                    }

                    Button("Save check-in", action: onSaveMorningOutcomes)
                        .buttonStyle(WarmPrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(AccessibilityID.exploreMorningSaveButton)
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

    @State private var isOptionsPresented = false
    @State private var selectedGraphDetail: SituationGraphDetail?

    var body: some View {
        NavigationStack {
            GraphWebView(
                graphData: graphData,
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
            .sheet(item: $selectedGraphDetail) { detail in
                SituationGraphDetailSheet(detail: detail)
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier(AccessibilityID.exploreDetailsSheet)
            }
        }
    }

    private func handleGraphEvent(_ event: GraphEvent) {
        onGraphEvent(event)

        switch event {
        case .nodeSelected(let id, let label):
            selectedGraphDetail = SituationGraphDetail(
                id: UUID(),
                detail: .node(nodeDetail(forNodeID: id, fallbackLabel: label))
            )
        case .edgeSelected(let sourceID, let targetID, let sourceLabel, let targetLabel, let label):
            selectedGraphDetail = SituationGraphDetail(
                id: UUID(),
                detail: .edge(
                    edgeDetail(
                        sourceID: sourceID,
                        targetID: targetID,
                        sourceLabel: sourceLabel,
                        targetLabel: targetLabel,
                        label: label
                    )
                )
            )
        case .graphReady, .viewportChanged, .renderError:
            return
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
                mechanism: nil
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
            mechanism: node.tooltip?.mechanism
        )
    }

    private func edgeDetail(
        sourceID: String,
        targetID: String,
        sourceLabel: String,
        targetLabel: String,
        label: String?
    ) -> SituationEdgeDetail {
        let nodeLabelByID = Dictionary(
            uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, firstLine($0.data.label)) }
        )

        let matchedEdge = graphData.edges.first {
            $0.data.source == sourceID
                && $0.data.target == targetID
                && ($0.data.label == label || label == nil)
        }?.data ?? graphData.edges.first {
            let edgeSourceLabel = nodeLabelByID[$0.data.source] ?? $0.data.source
            let edgeTargetLabel = nodeLabelByID[$0.data.target] ?? $0.data.target
            return edgeSourceLabel == sourceLabel
                && edgeTargetLabel == targetLabel
                && ($0.data.label == label || label == nil)
        }?.data

        return SituationEdgeDetail(
            sourceID: sourceID,
            targetID: targetID,
            sourceLabel: sourceLabel,
            targetLabel: targetLabel,
            label: matchedEdge?.label ?? label,
            edgeType: matchedEdge?.edgeType,
            tooltip: matchedEdge?.tooltip,
            edgeColor: matchedEdge?.edgeColor
        )
    }

    private func firstLine(_ value: String) -> String {
        value.components(separatedBy: "\n").first ?? value
    }
}

private struct SituationGraphDetail: Identifiable, Equatable {
    let id: UUID
    let detail: SituationGraphDetailContent
}

private enum SituationGraphDetailContent: Equatable {
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
}

private struct SituationGraphDetailSheet: View {
    let detail: SituationGraphDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                    switch detail.detail {
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

    // MARK: - Node Content

    @ViewBuilder
    private func nodeContent(_ node: SituationNodeDetail) -> some View {
        // Header with colored indicator
        HStack(spacing: TelocareTheme.Spacing.sm) {
            Circle()
                .fill(accentColor(for: node.styleClass))
                .frame(width: 12, height: 12)
            Text(node.label)
                .font(.title2.bold())
                .foregroundStyle(TelocareTheme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Node info card
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Node Info")
                DetailRow(label: "Type", value: displayName(for: node.styleClass))
                if let tier = node.tier {
                    DetailRow(label: "Tier", value: String(tier))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .stroke(accentColor(for: node.styleClass), lineWidth: 2)
        )

        // Evidence card
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

    // MARK: - Edge Content

    @ViewBuilder
    private func edgeContent(_ edge: SituationEdgeDetail) -> some View {
        let edgeAccent = edgeAccentColor(for: edge.edgeType, color: edge.edgeColor)

        // Header showing link direction
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

        // Link details card
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Details")
                if let label = edge.label, !label.isEmpty {
                    DetailRow(label: "Label", value: label)
                }
                if let edgeType = edge.edgeType {
                    DetailRow(label: "Type", value: edgeType.capitalized)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                .stroke(edgeAccent, lineWidth: 2)
        )

        // Explanation card
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

    // MARK: - Helpers

    private func accentColor(for styleClass: String?) -> Color {
        switch styleClass?.lowercased() {
        case "robust":
            return Color(red: 0.52, green: 0.76, blue: 0.56) // #85C28F
        case "moderate":
            return Color(red: 1.0, green: 0.6, blue: 0.4)    // #FF9966
        case "preliminary":
            return Color(red: 0.83, green: 0.65, blue: 1.0)  // #D4A5FF
        case "mechanism":
            return Color(red: 0.49, green: 0.83, blue: 0.99) // #7DD3FC
        case "symptom":
            return TelocareTheme.coral                        // #FF7060
        case "intervention":
            return TelocareTheme.coral                        // #FF7060
        default:
            return TelocareTheme.warmGray
        }
    }

    private func edgeAccentColor(for edgeType: String?, color: String?) -> Color {
        // First check explicit color
        if let color = color?.lowercased() {
            if color.contains("green") || color.contains("protective") {
                return Color(red: 0.52, green: 0.76, blue: 0.56)
            }
            if color.contains("red") || color.contains("harmful") {
                return TelocareTheme.coral
            }
        }
        // Then check edge type
        switch edgeType?.lowercased() {
        case "protective", "inhibits":
            return Color(red: 0.52, green: 0.76, blue: 0.56)
        case "causal", "causes", "triggers":
            return TelocareTheme.coral
        case "feedback":
            return Color(red: 1.0, green: 0.6, blue: 0.4)
        default:
            return TelocareTheme.warmGray
        }
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

    @State private var navigationPath = NavigationPath()
    @State private var filterMode: InputFilterMode = .all

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
            .navigationDestination(for: InputStatus.self) { input in
                InputDetailView(input: input, graphData: graphData)
                    .accessibilityIdentifier(AccessibilityID.exploreInputDetailSheet)
            }
        }
    }

    private func showInputDetail(_ input: InputStatus) {
        navigationPath.append(input)
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
        case .all:
            return inputs.filter { !$0.isHidden }.count
        case .pending:
            return inputs.filter { !$0.isHidden && !$0.isCheckedToday }.count
        case .completed:
            return inputs.filter { !$0.isHidden && $0.isCheckedToday }.count
        case .hidden:
            return inputs.filter(\.isHidden).count
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
                            onShowDetails: { showInputDetail(input) }
                        )
                    }
                }
                .padding(TelocareTheme.Spacing.md)
            }
        }
    }

    private var filteredInputs: [InputStatus] {
        switch filterMode {
        case .all:
            return inputs.filter { !$0.isHidden }
        case .pending:
            return inputs.filter { !$0.isHidden && !$0.isCheckedToday }
        case .completed:
            return inputs.filter { !$0.isHidden && $0.isCheckedToday }
        case .hidden:
            return inputs.filter(\.isHidden)
        }
    }

    private var visibleInputs: [InputStatus] {
        inputs.filter { !$0.isHidden }
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
        case .all, .pending:
            return "No interventions to show.\nThey'll appear as you add them."
        case .completed:
            return "Nothing completed yet today.\nTap an intervention to check it off!"
        case .hidden:
            return "No hidden interventions."
        }
    }
}

// MARK: - Filter Mode

private enum InputFilterMode: CaseIterable {
    case all, pending, completed, hidden

    var title: String {
        switch self {
        case .all:
            return "All"
        case .pending:
            return "To do"
        case .completed:
            return "Done"
        case .hidden:
            return "Hidden"
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
    let onShowDetails: () -> Void

    var body: some View {
        WarmCard(padding: 0) {
            HStack(spacing: 0) {
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
                .padding(.leading, TelocareTheme.Spacing.sm)
                .padding(.vertical, TelocareTheme.Spacing.sm)
                .accessibilityLabel(input.isCheckedToday ? "Uncheck \(input.name)" : "Check \(input.name)")

                Button(action: onShowDetails) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.name)
                                .font(TelocareTheme.Typography.headline)
                                .foregroundStyle(input.isCheckedToday ? TelocareTheme.muted : TelocareTheme.charcoal)
                                .strikethrough(input.isCheckedToday)

                            HStack(spacing: TelocareTheme.Spacing.sm) {
                                WeeklyProgressBar(completion: input.completion)

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                Text(input.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)

                statusCard
                evidenceCard

                if input.detailedDescription != nil {
                    descriptionCard
                }

                if input.externalLink != nil {
                    linkCard
                }
            }
            .padding(TelocareTheme.Spacing.md)
        }
        .background(TelocareTheme.sand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Status")

                DetailRow(label: "Status", value: input.statusText)
                DetailRow(label: "7-day completion", value: "\(Int((input.completion * 100).rounded()))%")
                DetailRow(label: "Checked today", value: input.isCheckedToday ? "Yes" : "No")

                if let classification = input.classificationText {
                    DetailRow(label: "Classification", value: classification)
                }

                if input.isHidden {
                    HStack {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(TelocareTheme.warmGray)
                        Text("Hidden on web")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                    }
                    .padding(.top, TelocareTheme.Spacing.xs)
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
        graphData.nodes.first { $0.data.id == input.id }?.data
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
