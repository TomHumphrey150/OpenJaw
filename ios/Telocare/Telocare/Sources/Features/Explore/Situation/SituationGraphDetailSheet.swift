import SwiftUI

enum SituationGraphSelection: Identifiable, Equatable {
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

struct SituationEdgeSelection: Equatable {
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

enum SituationGraphDetail: Equatable {
    case node(SituationNodeDetail)
    case edge(SituationEdgeDetail)
}

struct SituationNodeDetail: Equatable {
    let id: String
    let label: String
    let styleClass: String?
    let tier: Int?
    let evidence: String?
    let statistic: String?
    let citation: String?
    let mechanism: String?
    let isDeactivated: Bool
    let childNodeCount: Int
    let isExpanded: Bool
}

struct SituationEdgeDetail: Equatable {
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

struct SituationGraphDetailSheet: View {
    let detail: SituationGraphDetail
    let onToggleNodeDeactivated: (String) -> Void
    let onToggleEdgeDeactivated: (String, String, String?, String?) -> Void
    let onToggleNodeExpanded: (String) -> Void
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
                .font(TelocareTheme.Typography.title.weight(.bold))
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
                DetailRow(label: "Branch", value: branchStatusText(node))
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

        if node.childNodeCount > 0 {
            WarmCard {
                Button {
                    onToggleNodeExpanded(node.id)
                } label: {
                    HStack(spacing: TelocareTheme.Spacing.sm) {
                        Text(
                            node.isExpanded
                                ? "Collapse branch (\(node.childNodeCount) nodes)"
                                : "Expand branch (\(node.childNodeCount) nodes)"
                        )
                        .font(TelocareTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(TelocareTheme.charcoal)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, TelocareTheme.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.exploreDetailsNodeBranchToggleButton)
                .accessibilityValue(node.isExpanded ? "Expanded" : "Collapsed")
            }
        }

        WarmCard {
            Button {
                onToggleNodeDeactivated(node.id)
            } label: {
                HStack(spacing: TelocareTheme.Spacing.sm) {
                    Text(node.isDeactivated ? "Reactivate node" : "Deactivate node")
                        .font(TelocareTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(TelocareTheme.charcoal)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, TelocareTheme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                    .font(TelocareTheme.Typography.title.weight(.bold))
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
            Button {
                onToggleEdgeDeactivated(
                    edge.sourceID,
                    edge.targetID,
                    edge.label,
                    edge.edgeType
                )
            } label: {
                HStack(spacing: TelocareTheme.Spacing.sm) {
                    Text(edge.isExplicitlyDeactivated ? "Reactivate link" : "Deactivate link")
                        .font(TelocareTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(TelocareTheme.charcoal)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, TelocareTheme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    private func branchStatusText(_ node: SituationNodeDetail) -> String {
        if node.childNodeCount == 0 {
            return "Leaf node"
        }

        let state = node.isExpanded ? "Expanded" : "Collapsed"
        return "\(state), \(node.childNodeCount) direct children (some shared across branches)"
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

struct SituationOptionsSheet: View {
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
                        .font(TelocareTheme.Typography.caption)
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
                        .font(TelocareTheme.Typography.caption)
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
                        .font(TelocareTheme.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(TelocareTheme.sand)
            .navigationTitle("Map Options")
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

