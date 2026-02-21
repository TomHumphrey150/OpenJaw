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

    @State private var selectedRecord: OutcomeRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MorningOutcomeEditor(
                        selection: morningOutcomeSelection,
                        onSetValue: onSetMorningOutcomeValue,
                        onSave: onSaveMorningOutcomes
                    )

                    Divider()

                    Text("Explore Mode")
                        .font(.headline)
                    LabeledContent("Shield score", value: "\(outcomes.shieldScore)")
                    LabeledContent("RMMA burden trend", value: "\(outcomes.burdenTrendPercent)%")
                    LabeledContent("Top contributor", value: outcomes.topContributor)
                    LabeledContent("Confidence", value: outcomes.confidence)

                    Divider()

                    Text("Night outcomes")
                        .font(.headline)

                    if outcomeRecords.isEmpty {
                        Text("No night outcomes have been recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(outcomeRecords) { record in
                                Button {
                                    selectedRecord = record
                                } label: {
                                    OutcomeRecordRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Outcomes")
            .sheet(item: $selectedRecord) { record in
                OutcomeRecordDetailSheet(record: record, outcomesMetadata: outcomesMetadata)
                    .accessibilityIdentifier(AccessibilityID.exploreOutcomeDetailSheet)
            }
        }
    }
}

private struct MorningOutcomeEditor: View {
    let selection: MorningOutcomeSelection
    let onSetValue: (Int?, MorningOutcomeField) -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Morning check-in")
                .font(.headline)
            Text("Night \(selection.nightID)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Score once after waking. 0 is none, 5 is moderate, 10 is worst plausible.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(MorningOutcomeField.allCases) { field in
                MorningOutcomePickerRow(
                    title: field.title,
                    value: selection.value(for: field),
                    accessibilityIdentifier: field.accessibilityIdentifier,
                    onSetValue: { value in
                        onSetValue(value, field)
                    }
                )
            }

            Button("Save morning outcomes", action: onSave)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.exploreMorningSaveButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MorningOutcomePickerRow: View {
    let title: String
    let value: Int?
    let accessibilityIdentifier: String
    let onSetValue: (Int?) -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
            Spacer()
            Picker(title, selection: selectionBinding) {
                Text("Not set").tag(Optional<Int>.none)
                ForEach(0...10, id: \.self) { score in
                    Text(String(score)).tag(Optional<Int>.some(score))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private var selectionBinding: Binding<Int?> {
        Binding(
            get: { value },
            set: onSetValue
        )
    }
}

private struct OutcomeRecordRow: View {
    let record: OutcomeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.id)
                .font(.subheadline.weight(.semibold))
            LabeledContent("Microarousal rate", value: formatted(record.microArousalRatePerHour))
            LabeledContent("Microarousal count", value: formatted(record.microArousalCount))
            LabeledContent("Confidence", value: formatted(record.confidence))
            LabeledContent("Source", value: record.source ?? "Unknown")
            Text("Tap for details")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "Not recorded" }
        return String(format: "%.2f", value)
    }
}

private struct OutcomeRecordDetailSheet: View {
    let record: OutcomeRecord
    let outcomesMetadata: OutcomesMetadata
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Measured values") {
                    LabeledContent("Night", value: record.id)
                    LabeledContent("Microarousal rate/hour", value: formatted(record.microArousalRatePerHour))
                    LabeledContent("Microarousal count", value: formatted(record.microArousalCount))
                    LabeledContent("Confidence", value: formatted(record.confidence))
                    LabeledContent("Source", value: record.source ?? "Unknown")
                }

                Section("How to read this") {
                    if metricsForDisplay.isEmpty {
                        Text("Outcome metadata is not available yet.")
                    } else {
                        ForEach(metricsForDisplay, id: \.id) { metric in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(metric.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(metric.description)
                                    .foregroundStyle(.secondary)
                                LabeledContent("Unit", value: metric.unit)
                                LabeledContent("Direction", value: metric.direction.replacingOccurrences(of: "_", with: " "))
                            }
                        }
                    }
                }

                if !outcomeNodeEvidence.isEmpty {
                    Section("Outcome pathway evidence") {
                        ForEach(outcomeNodeEvidence) { node in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(node.label)
                                    .font(.subheadline.weight(.semibold))
                                if let evidence = node.evidence {
                                    LabeledContent("Evidence", value: evidence)
                                }
                                if let stat = node.stat {
                                    LabeledContent("Statistic", value: stat)
                                }
                                if let citation = node.citation {
                                    LabeledContent("Citation", value: citation)
                                }
                                if let mechanism = node.mechanism {
                                    LabeledContent("Mechanism", value: mechanism)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Outcome Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
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
            List {
                switch detail.detail {
                case .node(let node):
                    nodeSection(node)
                case .edge(let edge):
                    edgeSection(edge)
                }
            }
            .navigationTitle("Graph Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nodeSection(_ node: SituationNodeDetail) -> some View {
        Section("Node") {
            LabeledContent("Label", value: node.label)
            LabeledContent("Node ID", value: node.id)
            LabeledContent("Style", value: node.styleClass ?? "Not provided")
            LabeledContent("Tier", value: node.tier.map(String.init) ?? "Not provided")
        }

        Section("Evidence") {
            LabeledContent("Evidence level", value: node.evidence ?? "Not provided")
            LabeledContent("Statistic", value: node.statistic ?? "Not provided")
            LabeledContent("Citation", value: node.citation ?? "Not provided")
            LabeledContent("Mechanism", value: node.mechanism ?? "Not provided")
        }
    }

    @ViewBuilder
    private func edgeSection(_ edge: SituationEdgeDetail) -> some View {
        Section("Link") {
            LabeledContent("From", value: edge.sourceLabel)
            LabeledContent("To", value: edge.targetLabel)
            LabeledContent("Source ID", value: edge.sourceID)
            LabeledContent("Target ID", value: edge.targetID)
            LabeledContent("Label", value: edge.label ?? "Not provided")
            LabeledContent("Type", value: edge.edgeType ?? "Not provided")
            LabeledContent("Color", value: edge.edgeColor ?? "Not provided")
        }

        Section("Explanation") {
            Text(edge.tooltip ?? "No explanation is available for this link yet.")
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
                Section("Selection") {
                    Text(graphSelectionText)
                    LabeledContent("Focused node", value: situation.focusedNode)
                    LabeledContent("Visible hotspots", value: "\(situation.visibleHotspots)")
                }

                Section("Display") {
                    Toggle(
                        "Show intervention nodes",
                        isOn: Binding(
                            get: { displayFlags.showInterventionNodes },
                            set: onShowInterventionsChanged
                        )
                    )
                    .accessibilityIdentifier(AccessibilityID.exploreToggleInterventions)

                    Toggle(
                        "Show feedback edges",
                        isOn: Binding(
                            get: { displayFlags.showFeedbackEdges },
                            set: onShowFeedbackEdgesChanged
                        )
                    )
                    .accessibilityIdentifier(AccessibilityID.exploreToggleFeedbackEdges)

                    Toggle(
                        "Show protective edges",
                        isOn: Binding(
                            get: { displayFlags.showProtectiveEdges },
                            set: onShowProtectiveEdgesChanged
                        )
                    )
                    .accessibilityIdentifier(AccessibilityID.exploreToggleProtectiveEdges)
                }

                Section("Actions") {
                    ForEach(ExploreContextAction.allCases) { action in
                        Button(action.title) {
                            onAction(action)
                        }
                        .accessibilityIdentifier(action.accessibilityIdentifier)
                    }
                }
            }
            .navigationTitle("Situation Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ExploreInputsScreen: View {
    let inputs: [InputStatus]
    let graphData: CausalGraphData
    let onToggleCheckedToday: (String) -> Void

    @State private var selectedInput: InputStatus?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Inputs")
                .sheet(item: $selectedInput) { input in
                    InputDetailSheet(input: input, graphData: graphData)
                        .accessibilityIdentifier(AccessibilityID.exploreInputDetailSheet)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if inputs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("No intervention check-ins have been recorded yet.")
                    .foregroundStyle(.secondary)
                Text("As check-ins are saved, they will appear here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List {
                if !visibleInputs.isEmpty {
                    Section("Visible interventions") {
                        ForEach(visibleInputs) { input in
                            InputStatusRow(
                                input: input,
                                onToggleCheckedToday: {
                                    onToggleCheckedToday(input.id)
                                },
                                onShowDetails: {
                                    selectedInput = input
                                }
                            )
                        }
                    }
                }

                if !hiddenInputs.isEmpty {
                    Section("Hidden interventions") {
                        ForEach(hiddenInputs) { input in
                            InputStatusRow(
                                input: input,
                                onToggleCheckedToday: {
                                    onToggleCheckedToday(input.id)
                                },
                                onShowDetails: {
                                    selectedInput = input
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var visibleInputs: [InputStatus] {
        inputs.filter { !$0.isHidden }
    }

    private var hiddenInputs: [InputStatus] {
        inputs.filter { $0.isHidden }
    }
}

private struct InputStatusRow: View {
    let input: InputStatus
    let onToggleCheckedToday: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCheckedToday) {
                Image(systemName: input.isCheckedToday ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(input.isCheckedToday ? "Uncheck \(input.name)" : "Check \(input.name)")

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(input.name, value: input.statusText)

                if let classification = input.classificationText {
                    LabeledContent("Classification", value: classification)
                }

                if let evidenceLevel = input.evidenceLevel {
                    LabeledContent("Evidence", value: evidenceLevel)
                }

                if input.isHidden {
                    Text("Hidden on web")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: input.completion)
            }

            Spacer(minLength: 12)

            Button("Details", action: onShowDetails)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

private struct InputDetailSheet: View {
    let input: InputStatus
    let graphData: CausalGraphData

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Current status") {
                    LabeledContent("Name", value: input.name)
                    LabeledContent("Status", value: input.statusText)
                    LabeledContent("7-day completion", value: "\(Int((input.completion * 100).rounded()))%")
                    LabeledContent("Checked today", value: input.isCheckedToday ? "Yes" : "No")
                    LabeledContent("Classification", value: input.classificationText ?? "Unknown")
                    LabeledContent("Hidden on web", value: input.isHidden ? "Yes" : "No")
                }

                Section("Graph metadata") {
                    if let node = graphNodeData {
                        LabeledContent("Node ID", value: node.id)
                        LabeledContent("Style", value: node.styleClass)
                        LabeledContent("Tier", value: node.tier.map(String.init) ?? "Not set")
                        LabeledContent("Label", value: firstLine(node.label))
                    } else {
                        Text("No graph node metadata is available for this intervention.")
                    }
                }

                Section("Evidence") {
                    LabeledContent("Evidence", value: input.evidenceLevel ?? graphNodeData?.tooltip?.evidence ?? "Not provided")
                    LabeledContent("Summary", value: input.evidenceSummary ?? graphNodeData?.tooltip?.mechanism ?? "Not provided")
                    LabeledContent("Citation IDs", value: citationValue)
                    LabeledContent("Citation", value: graphNodeData?.tooltip?.citation ?? "Not provided")
                    LabeledContent("Statistic", value: graphNodeData?.tooltip?.stat ?? "Not provided")
                }

                if let detailedDescription = input.detailedDescription {
                    Section("Detailed description") {
                        Text(detailedDescription)
                    }
                }

                if let externalLink = input.externalLink {
                    Section("Reference link") {
                        Text(externalLink)
                    }
                }
            }
            .navigationTitle("Input Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var graphNodeData: GraphNodeData? {
        graphData.nodes.first { $0.data.id == input.id }?.data
    }

    private func firstLine(_ text: String) -> String {
        text.components(separatedBy: "\n").first ?? text
    }

    private var citationValue: String {
        if !input.citationIDs.isEmpty {
            return input.citationIDs.joined(separator: ", ")
        }

        return "Not provided"
    }
}

private struct ExploreChatScreen: View {
    @Binding var draft: String
    let feedback: String
    let onSend: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("AI chat backend not connected yet", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(AccessibilityID.exploreChatInput)
                Button("Send (placeholder)", action: onSend)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.exploreChatSendButton)
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.exploreFeedbackText)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Chat")
        }
    }
}
