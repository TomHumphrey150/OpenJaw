import SwiftUI

struct ExploreTabShell: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView(selection: selectedTabBinding) {
            ExploreOutcomesScreen(outcomes: viewModel.snapshot.outcomes)
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
                onAction: viewModel.performExploreAction
            )
            .tabItem { Label(ExploreTab.situation.title, systemImage: ExploreTab.situation.symbolName) }
            .tag(ExploreTab.situation)
            .accessibilityIdentifier(AccessibilityID.exploreSituationScreen)

            ExploreInputsScreen(inputs: viewModel.snapshot.inputs)
                .tabItem { Label(ExploreTab.inputs.title, systemImage: ExploreTab.inputs.symbolName) }
                .tag(ExploreTab.inputs)
                .accessibilityIdentifier(AccessibilityID.exploreInputsScreen)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExploreChatBar(
                draft: $viewModel.chatDraft,
                feedback: viewModel.exploreFeedback,
                onSend: viewModel.submitChatPrompt
            )
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
                }
                .padding()
                .padding(.top, 54)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Outcomes")
        }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Long-press the graph or use an action button.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    GraphWebView(
                        graphData: graphData,
                        displayFlags: displayFlags,
                        focusedNodeID: focusedNodeID,
                        onEvent: onGraphEvent
                    )
                        .frame(height: 310)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator), lineWidth: 1)
                        )
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
                    Text(graphSelectionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.graphSelectionText)
                    LabeledContent("Focused node", value: situation.focusedNode)
                    LabeledContent("Visible hotspots", value: "\(situation.visibleHotspots)")
                    actionButtons
                }
                .padding()
                .padding(.top, 54)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Situation")
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ExploreContextAction.allCases) { action in
                Button(action.title) {
                    onAction(action)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
    }
}

private struct ExploreInputsScreen: View {
    let inputs: [InputStatus]

    var body: some View {
        NavigationStack {
            List(inputs) { input in
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(input.name, value: input.statusText)
                    ProgressView(value: input.completion)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Inputs")
            .padding(.top, 54)
        }
    }
}

private struct ExploreChatBar: View {
    @Binding var draft: String
    let feedback: String
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ask for a typed AI change", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityID.exploreChatInput)
            Button("Send to AI", action: onSend)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.exploreChatSendButton)
            Text(feedback)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.exploreFeedbackText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}
