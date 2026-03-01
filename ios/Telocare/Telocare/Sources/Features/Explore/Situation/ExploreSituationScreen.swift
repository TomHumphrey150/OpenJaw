import SwiftUI

enum SituationMapMode: String, CaseIterable, Identifiable {
    case pager
    case fullGraph

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pager:
            return "Pager"
        case .fullGraph:
            return "Full Graph"
        }
    }
}

struct ExploreSituationScreen: View {
    let situation: SituationSummary
    let graphData: CausalGraphData
    let graphVersionHint: String?
    let displayFlags: GraphDisplayFlags
    let focusedNodeID: String?
    let graphSelectionText: String
    let inputs: [InputStatus]
    let planningMetadataByInterventionID: [String: HabitPlanningMetadata]
    let orderedPillars: [HealthPillarDefinition]
    let pillarAssignments: [PillarAssignment]
    let selectedLensMode: HealthLensMode
    let selectedLensPillars: [HealthPillar]
    let selectedLensIsAllSelected: Bool
    let onGraphEvent: (GraphEvent) -> Void
    let onAction: (ExploreContextAction) -> Void
    let onShowInterventionsChanged: (Bool) -> Void
    let onShowFeedbackEdgesChanged: (Bool) -> Void
    let onShowProtectiveEdgesChanged: (Bool) -> Void
    let onToggleNodeDeactivated: (String) -> Void
    let onToggleNodeExpanded: (String) -> Void
    let onToggleEdgeDeactivated: (String, String, String?, String?) -> Void
    let isLensFilteredEmpty: Bool
    let emptyLensMessage: String
    let onClearLensFilter: () -> Void
    let selectedSkinID: TelocareSkinID

    @State private var mapMode: SituationMapMode = .pager
    @State private var showPagerInterventions = false
    @State private var selectedNeighborhoodIndex = 0
    @State private var isOptionsPresented = false
    @State private var selectedGraphSelection: SituationGraphSelection?

    private let neighborhoodBuilder = PillarNeighborhoodBuilder()

    var body: some View {
        NavigationStack {
            VStack(spacing: TelocareTheme.Spacing.sm) {
                if mapMode == .pager, let activeNeighborhood {
                    pagerHeader(activeNeighborhood)
                        .padding(.horizontal, 12)
                }

                graphSurface
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

                if mapMode == .pager, !neighborhoods.isEmpty {
                    pagerControls
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
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
                    mapMode: mapMode,
                    showPagerInterventions: showPagerInterventions,
                    onMapModeChanged: { nextMode in
                        mapMode = nextMode
                    },
                    onShowPagerInterventionsChanged: { isVisible in
                        showPagerInterventions = isVisible
                    },
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
            .onChange(of: neighborhoods.map(\.id)) { _, ids in
                if ids.isEmpty {
                    selectedNeighborhoodIndex = 0
                    return
                }

                selectedNeighborhoodIndex = min(selectedNeighborhoodIndex, ids.count - 1)
            }
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
    }

    @ViewBuilder
    private var graphSurface: some View {
        GraphWebView(
            graphData: activeGraphData,
            graphVersionHint: activeGraphVersionHint,
            graphSkin: TelocareTheme.graphSkin,
            displayFlags: activeDisplayFlags,
            focusedNodeID: activeFocusedNodeID,
            onEvent: handleGraphEvent
        )
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
        .overlay {
            if isLensFilteredEmpty {
                VStack(spacing: TelocareTheme.Spacing.sm) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(TelocareTheme.warmGray)
                    Text(emptyLensMessage)
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.charcoal)
                        .multilineTextAlignment(.center)
                    Button("Clear filter") {
                        onClearLensFilter()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(TelocareTheme.Spacing.lg)
                .background(
                    RoundedRectangle(
                        cornerRadius: TelocareTheme.CornerRadius.large,
                        style: .continuous
                    )
                    .fill(TelocareTheme.cream)
                )
                .padding(TelocareTheme.Spacing.lg)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard mapMode == .pager else { return }
                    guard !neighborhoods.isEmpty else { return }

                    if value.translation.height <= -42 {
                        moveToNextNeighborhood()
                        return
                    }
                    if value.translation.height >= 42 {
                        moveToPreviousNeighborhood()
                    }
                }
        )
    }

    private var neighborhoods: [PillarNeighborhood] {
        neighborhoodBuilder.build(
            graphData: graphData,
            inputs: inputs,
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            orderedPillars: orderedPillars,
            pillarAssignments: pillarAssignments,
            selectedLensMode: selectedLensMode,
            selectedLensPillars: selectedLensPillars,
            selectedLensIsAllSelected: selectedLensIsAllSelected,
            graphVersionHint: graphVersionHint
        )
    }

    private var activeNeighborhood: PillarNeighborhood? {
        guard !neighborhoods.isEmpty else {
            return nil
        }
        let safeIndex = min(max(0, selectedNeighborhoodIndex), neighborhoods.count - 1)
        return neighborhoods[safeIndex]
    }

    private var activeGraphData: CausalGraphData {
        if mapMode == .fullGraph {
            return graphData
        }
        if neighborhoods.isEmpty {
            return CausalGraphData(nodes: [], edges: [])
        }
        return activeNeighborhood?.graphData ?? graphData
    }

    private var activeGraphVersionHint: String? {
        if mapMode == .fullGraph || neighborhoods.isEmpty {
            return graphVersionHint
        }
        guard let activeNeighborhood else {
            return graphVersionHint
        }
        let fingerprint = activeNeighborhood.graphData.nodes.map { $0.data.id }.joined(separator: "|")
        let hash = String(fingerprint.hashValue, radix: 16)
        if let graphVersionHint {
            return "\(graphVersionHint):\(activeNeighborhood.pillar.id):\(hash)"
        }
        return "\(activeNeighborhood.pillar.id):\(hash)"
    }

    private var activeDisplayFlags: GraphDisplayFlags {
        if mapMode == .fullGraph || neighborhoods.isEmpty {
            return displayFlags
        }
        let hasNonInterventionNodes = activeNeighborhood?.graphData.nodes.contains { node in
            node.data.styleClass != "intervention"
        } ?? false
        let shouldShowInterventions = showPagerInterventions || !hasNonInterventionNodes

        return GraphDisplayFlags(
            showFeedbackEdges: displayFlags.showFeedbackEdges,
            showProtectiveEdges: displayFlags.showProtectiveEdges,
            showInterventionNodes: shouldShowInterventions
        )
    }

    private var activeFocusedNodeID: String? {
        guard let focusedNodeID else {
            return nil
        }

        if activeGraphData.nodes.contains(where: { $0.data.id == focusedNodeID }) {
            return focusedNodeID
        }
        return nil
    }

    @ViewBuilder
    private func pagerHeader(_ neighborhood: PillarNeighborhood) -> some View {
        HStack(spacing: TelocareTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pillar neighborhood")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                Text(neighborhood.title)
                    .font(TelocareTheme.Typography.headline)
                    .foregroundStyle(TelocareTheme.charcoal)
            }

            Spacer()

            Text("\(selectedNeighborhoodIndex + 1) / \(neighborhoods.count)")
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
        }
        .accessibilityIdentifier(AccessibilityID.exploreSituationPagerHeader)
    }

    @ViewBuilder
    private var pagerControls: some View {
        HStack(spacing: TelocareTheme.Spacing.sm) {
            Button {
                moveToPreviousNeighborhood()
            } label: {
                Label("Previous", systemImage: "chevron.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(selectedNeighborhoodIndex == 0)
            .accessibilityIdentifier(AccessibilityID.exploreSituationPagerPrevious)

            Button {
                moveToNextNeighborhood()
            } label: {
                Label("Next", systemImage: "chevron.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedNeighborhoodIndex >= neighborhoods.count - 1)
            .accessibilityIdentifier(AccessibilityID.exploreSituationPagerNext)
        }
    }

    private func moveToNextNeighborhood() {
        guard !neighborhoods.isEmpty else {
            return
        }
        selectedNeighborhoodIndex = min(selectedNeighborhoodIndex + 1, neighborhoods.count - 1)
    }

    private func moveToPreviousNeighborhood() {
        guard !neighborhoods.isEmpty else {
            return
        }
        selectedNeighborhoodIndex = max(0, selectedNeighborhoodIndex - 1)
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
        let childNodeCount = activeGraphData.nodes.reduce(into: 0) { count, node in
            if node.data.parentIds?.contains(id) == true {
                count += 1
            }
        }

        guard let node = activeGraphData.nodes.first(where: { $0.data.id == id })?.data else {
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
            uniqueKeysWithValues: activeGraphData.nodes.map { ($0.data.id, firstLine($0.data.label)) }
        )

        let nodeByID = Dictionary(
            uniqueKeysWithValues: activeGraphData.nodes.map { ($0.data.id, $0.data) }
        )

        let matchedEdge = activeGraphData.edges.first {
            edgeIdentityMatches(
                edge: $0.data,
                sourceID: sourceID,
                targetID: targetID,
                label: label,
                edgeType: edgeType
            )
        }?.data ?? activeGraphData.edges.first {
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
