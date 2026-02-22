import SwiftUI

struct GuidedFlowPager: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            switch viewModel.guidedStep {
            case .outcomes:
                GuidedOutcomesScreen(
                    outcomes: viewModel.snapshot.outcomes,
                    onContinue: advanceFromOutcomes
                )
                .transition(screenTransition)
            case .situation:
                GuidedSituationScreen(
                    situation: viewModel.snapshot.situation,
                    graphData: viewModel.graphData,
                    displayFlags: viewModel.graphDisplayFlags,
                    focusedNodeID: viewModel.focusedNodeID,
                    graphSelectionText: viewModel.graphSelectionText,
                    onGraphEvent: viewModel.handleGraphEvent,
                    onContinue: advanceFromSituation
                )
                .transition(screenTransition)
            case .inputs:
                GuidedInputsScreen(
                    inputs: viewModel.snapshot.inputs,
                    onDone: completeGuidedFlow
                )
                .transition(screenTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advanceFromOutcomes() {
        withAnimation {
            viewModel.advanceFromOutcomes()
        }
    }

    private func advanceFromSituation() {
        withAnimation {
            viewModel.advanceFromSituation()
        }
    }

    private func completeGuidedFlow() {
        withAnimation {
            viewModel.completeGuidedFlow()
        }
    }
}

private struct GuidedOutcomesScreen: View {
    let outcomes: OutcomeSummary
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GuidedStepHeader(step: .outcomes)
                scoreCard
                outcomeRows
                ctaButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 66)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier(AccessibilityID.guidedOutcomesScreen)
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shield score")
                .font(.subheadline.weight(.semibold))
            Text("\(outcomes.shieldScore)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text("Last 7 days")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var outcomeRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("RMMA burden trend", value: "\(outcomes.burdenTrendPercent)%")
            ProgressView(value: outcomes.burdenProgress)
            LabeledContent("Top contributor", value: outcomes.topContributor)
            LabeledContent("Confidence", value: outcomes.confidence)
        }
    }

    private var ctaButton: some View {
        Button("Go to Situation", action: onContinue)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(AccessibilityID.guidedOutcomesCTA)
            .accessibilityLabel("Go to Situation")
            .accessibilityHint("Advances to step 2 of 3.")
    }
}

private struct GuidedSituationScreen: View {
    let situation: SituationSummary
    let graphData: CausalGraphData
    let displayFlags: GraphDisplayFlags
    let focusedNodeID: String?
    let graphSelectionText: String
    let onGraphEvent: (GraphEvent) -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GuidedStepHeader(step: .situation)
                GraphWebView(
                    graphData: graphData,
                    graphSkin: TelocareTheme.graphSkin,
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
                LabeledContent("Focused node", value: situation.focusedNode)
                LabeledContent("Tier", value: situation.tier)
                LabeledContent("Visible problems", value: "\(situation.visibleHotspots) hotspots")
                LabeledContent("Top source", value: situation.topSource)
                Text(graphSelectionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.graphSelectionText)
                Button("What can I do?", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(AccessibilityID.guidedSituationCTA)
                    .accessibilityLabel("What can I do?")
                    .accessibilityHint("Advances to step 3 of 3.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 66)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier(AccessibilityID.guidedSituationScreen)
    }
}

private struct GuidedInputsScreen: View {
    let inputs: [InputStatus]
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GuidedStepHeader(step: .inputs)
                inputRows
                Text("Finish this cycle to unlock Explore Mode controls.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(AccessibilityID.guidedDoneCTA)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Completes guided mode and opens Explore mode.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 66)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier(AccessibilityID.guidedInputsScreen)
    }

    private var inputRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(inputs) { input in
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(input.name, value: input.statusText)
                    ProgressView(value: input.completion)
                }
            }
        }
    }
}

private struct GuidedStepHeader: View {
    let step: GuidedStep

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guided Flow: Step \(step.position)/3 \(step.title)")
                .font(.title3.weight(.bold))
                .accessibilityIdentifier(AccessibilityID.guidedStepLabel)
            Text(step.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(GuidedStep.allCases, id: \.self) { item in
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(chipBackground(for: item))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func chipBackground(for item: GuidedStep) -> Color {
        item == step ? .teal.opacity(0.24) : Color(uiColor: .secondarySystemBackground)
    }
}
