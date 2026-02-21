import SwiftUI

struct ExploreTabShell: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView(selection: selectedTabBinding) {
            ExploreOutcomesScreen(
                outcomes: viewModel.snapshot.outcomes,
                outcomeRecords: viewModel.snapshot.outcomeRecords
            )
                .tabItem { Label(ExploreTab.outcomes.title, systemImage: ExploreTab.outcomes.symbolName) }
                .tag(ExploreTab.outcomes)
                .accessibilityIdentifier(AccessibilityID.exploreOutcomesScreen)

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

            ExploreInputsScreen(
                inputs: viewModel.snapshot.inputs,
                graphData: viewModel.graphData,
                onToggleCheckedToday: viewModel.toggleInputCheckedToday
            )
                .tabItem { Label(ExploreTab.inputs.title, systemImage: ExploreTab.inputs.symbolName) }
                .tag(ExploreTab.inputs)
                .accessibilityIdentifier(AccessibilityID.exploreInputsScreen)

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

    @State private var selectedRecord: OutcomeRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                OutcomeRecordDetailSheet(record: record)
                    .accessibilityIdentifier(AccessibilityID.exploreOutcomeDetailSheet)
            }
        }
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
                    Text("Microarousal rate tracks event frequency per hour; lower values indicate calmer sleep.")
                    Text("Confidence is model certainty for this value, where higher is stronger.")
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

    var body: some View {
        NavigationStack {
            GraphWebView(
                graphData: graphData,
                displayFlags: displayFlags,
                focusedNodeID: focusedNodeID,
                onEvent: onGraphEvent
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
                    if let tooltip = graphNodeData?.tooltip {
                        LabeledContent("Evidence", value: tooltip.evidence ?? "Not provided")
                        LabeledContent("Statistic", value: tooltip.stat ?? "Not provided")
                        LabeledContent("Citation", value: tooltip.citation ?? "Not provided")
                        LabeledContent("Mechanism", value: tooltip.mechanism ?? "Not provided")
                    } else {
                        Text("No evidence details are available for this intervention.")
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
