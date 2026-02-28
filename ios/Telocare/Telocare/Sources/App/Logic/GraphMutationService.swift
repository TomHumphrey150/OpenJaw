import Foundation

protocol GraphMutationService {
    func toggleNodeDeactivation(
        nodeID: String,
        graphData: CausalGraphData,
        at now: Date
    ) -> GraphMutationResult?

    func toggleEdgeDeactivation(
        sourceID: String,
        targetID: String,
        label: String?,
        edgeType: String?,
        graphData: CausalGraphData,
        at now: Date
    ) -> GraphMutationResult?

    func toggleNodeExpansion(
        nodeID: String,
        graphData: CausalGraphData,
        at now: Date
    ) -> GraphMutationResult?
}

struct GraphMutationResult {
    let graphData: CausalGraphData
    let patch: UserDataPatch
    let successMessage: String
    let failureMessage: String
}

struct DefaultGraphMutationService: GraphMutationService {
    func toggleNodeDeactivation(
        nodeID: String,
        graphData: CausalGraphData,
        at now: Date
    ) -> GraphMutationResult? {
        guard let nodeIndex = graphData.nodes.firstIndex(where: { $0.data.id == nodeID }) else {
            return nil
        }

        let currentNode = graphData.nodes[nodeIndex].data
        let nextIsDeactivated = !(currentNode.isDeactivated ?? false)

        var nextNodes = graphData.nodes
        nextNodes[nodeIndex] = GraphNodeElement(
            data: GraphNodeData(
                id: currentNode.id,
                label: currentNode.label,
                styleClass: currentNode.styleClass,
                confirmed: currentNode.confirmed,
                tier: currentNode.tier,
                tooltip: currentNode.tooltip,
                isDeactivated: nextIsDeactivated,
                parentIds: currentNode.parentIds,
                parentId: currentNode.parentId,
                isExpanded: currentNode.isExpanded
            )
        )

        let nextGraphData = CausalGraphData(
            nodes: nextNodes,
            edges: graphData.edges
        )

        let nodeLabel = GraphIdentityMatcher.firstLine(currentNode.label)
        let successMessage = nextIsDeactivated
            ? "\(nodeLabel) deactivated."
            : "\(nodeLabel) reactivated."
        let failureMessage = "Could not save \(nodeLabel) state. Reverted."

        return GraphMutationResult(
            graphData: nextGraphData,
            patch: graphDeactivationPatch(for: nextGraphData, at: now),
            successMessage: successMessage,
            failureMessage: failureMessage
        )
    }

    func toggleEdgeDeactivation(
        sourceID: String,
        targetID: String,
        label: String?,
        edgeType: String?,
        graphData: CausalGraphData,
        at now: Date
    ) -> GraphMutationResult? {
        guard let edgeIndex = graphData.edges.firstIndex(where: {
            GraphIdentityMatcher.edgeIdentityMatches(
                edgeData: $0.data,
                sourceID: sourceID,
                targetID: targetID,
                label: label,
                edgeType: edgeType
            )
        }) else {
            return nil
        }

        let currentEdge = graphData.edges[edgeIndex].data
        let nextIsDeactivated = !(currentEdge.isDeactivated ?? false)

        var nextEdges = graphData.edges
        nextEdges[edgeIndex] = GraphEdgeElement(
            data: GraphEdgeData(
                id: currentEdge.id,
                source: currentEdge.source,
                target: currentEdge.target,
                label: currentEdge.label,
                edgeType: currentEdge.edgeType,
                edgeColor: currentEdge.edgeColor,
                tooltip: currentEdge.tooltip,
                strength: currentEdge.strength,
                isDeactivated: nextIsDeactivated
            )
        )

        let nextGraphData = CausalGraphData(
            nodes: graphData.nodes,
            edges: nextEdges
        )

        let edgeText = edgeDescription(sourceID: sourceID, targetID: targetID, graphData: graphData)
        let successMessage = nextIsDeactivated
            ? "Link \(edgeText) deactivated."
            : "Link \(edgeText) reactivated."
        let failureMessage = "Could not save link \(edgeText) state. Reverted."

        return GraphMutationResult(
            graphData: nextGraphData,
            patch: graphDeactivationPatch(for: nextGraphData, at: now),
            successMessage: successMessage,
            failureMessage: failureMessage
        )
    }

    func toggleNodeExpansion(
        nodeID: String,
        graphData: CausalGraphData,
        at now: Date
    ) -> GraphMutationResult? {
        guard let nodeIndex = graphData.nodes.firstIndex(where: { $0.data.id == nodeID }) else {
            return nil
        }

        let childCount = graphData.nodes.reduce(into: 0) { count, node in
            if node.data.parentIds?.contains(nodeID) == true {
                count += 1
            }
        }
        guard childCount > 0 else {
            return nil
        }

        let currentNode = graphData.nodes[nodeIndex].data
        let nextIsExpanded = !(currentNode.isExpanded ?? true)

        var nextNodes = graphData.nodes
        nextNodes[nodeIndex] = GraphNodeElement(
            data: GraphNodeData(
                id: currentNode.id,
                label: currentNode.label,
                styleClass: currentNode.styleClass,
                confirmed: currentNode.confirmed,
                tier: currentNode.tier,
                tooltip: currentNode.tooltip,
                isDeactivated: currentNode.isDeactivated,
                parentIds: currentNode.parentIds,
                parentId: currentNode.parentId,
                isExpanded: nextIsExpanded
            )
        )

        let nextGraphData = CausalGraphData(
            nodes: nextNodes,
            edges: graphData.edges
        )

        let nodeLabel = GraphIdentityMatcher.firstLine(currentNode.label)
        let successMessage = nextIsExpanded
            ? "\(nodeLabel) branch expanded."
            : "\(nodeLabel) branch collapsed."
        let failureMessage = "Could not save \(nodeLabel) branch state. Reverted."

        return GraphMutationResult(
            graphData: nextGraphData,
            patch: graphDeactivationPatch(for: nextGraphData, at: now),
            successMessage: successMessage,
            failureMessage: failureMessage
        )
    }

    private func edgeDescription(
        sourceID: String,
        targetID: String,
        graphData: CausalGraphData
    ) -> String {
        let labelsByID = Dictionary(
            uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, GraphIdentityMatcher.firstLine($0.data.label)) }
        )
        let sourceLabel = labelsByID[sourceID] ?? sourceID
        let targetLabel = labelsByID[targetID] ?? targetID
        return "\(sourceLabel) to \(targetLabel)"
    }

    private func graphDeactivationPatch(for graphData: CausalGraphData, at now: Date) -> UserDataPatch {
        UserDataPatch.customCausalDiagram(
            CustomCausalDiagram(
                graphData: graphData,
                lastModified: DateKeying.timestamp(from: now),
                graphVersion: Self.graphVersion(for: graphData),
                baseGraphVersion: nil
            )
        )
    }

    private static func graphVersion(for graphData: CausalGraphData) -> String {
        var fingerprint = graphData.nodes
            .map { node in "\(node.data.id)|\(node.data.styleClass)|\(node.data.confirmed ?? "")|\(node.data.tier ?? -1)" }
            .sorted()
            .joined(separator: ";")
        fingerprint.append("|")
        fingerprint.append(
            graphData.edges
                .map { edge in
                    "\(edge.data.source)|\(edge.data.target)|\(edge.data.edgeType ?? "")|\(edge.data.label ?? "")|\(edge.data.strength ?? 0)"
                }
                .sorted()
                .joined(separator: ";")
        )

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in fingerprint.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        return String(format: "graph-%016llx", hash)
    }
}
