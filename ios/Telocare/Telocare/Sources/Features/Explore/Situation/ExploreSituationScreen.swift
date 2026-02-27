import SwiftUI

struct ExploreSituationScreen: View {
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
    let onToggleNodeExpanded: (String) -> Void
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
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(24)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(AccessibilityID.graphSelectionText)
            }
            .navigationTitle("My Map")
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
                    onToggleEdgeDeactivated: onToggleEdgeDeactivated,
                    onToggleNodeExpanded: onToggleNodeExpanded
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
        case .graphReady, .nodeDoubleTapped, .viewportChanged, .renderError:
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
        let childNodeCount = graphData.nodes.reduce(into: 0) { count, node in
            if node.data.parentIds?.contains(id) == true {
                count += 1
            }
        }

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
                isDeactivated: false,
                childNodeCount: childNodeCount,
                isExpanded: true
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
            isDeactivated: node.isDeactivated == true,
            childNodeCount: childNodeCount,
            isExpanded: node.isExpanded ?? true
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

