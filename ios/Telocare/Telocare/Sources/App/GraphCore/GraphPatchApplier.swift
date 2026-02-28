import Foundation

struct GraphPatchApplyResult: Equatable, Sendable {
    let diagram: CustomCausalDiagram
    let aliasOverrides: [GardenAliasOverride]
}

protocol GraphPatchApplier {
    func apply(
        _ envelope: GraphPatchEnvelope,
        to diagram: CustomCausalDiagram,
        aliasOverrides: [GardenAliasOverride]
    ) throws -> GraphPatchApplyResult
}

enum GraphPatchApplyError: Error {
    case invalidOperation(String)
}

struct DefaultGraphPatchApplier: GraphPatchApplier {
    func apply(
        _ envelope: GraphPatchEnvelope,
        to diagram: CustomCausalDiagram,
        aliasOverrides: [GardenAliasOverride]
    ) throws -> GraphPatchApplyResult {
        var nodes = diagram.graphData.nodes
        var edges = diagram.graphData.edges
        var nextAliasOverrides = aliasOverrides

        for operation in envelope.operations {
            switch operation.kind {
            case .addNode:
                guard let node = operation.node else {
                    throw GraphPatchApplyError.invalidOperation("addNode requires node payload")
                }
                if nodes.contains(where: { $0.data.id == node.id }) {
                    continue
                }
                nodes.append(GraphNodeElement(data: node))

            case .updateNode:
                guard let targetNodeID = operation.targetNodeID, let node = operation.node else {
                    throw GraphPatchApplyError.invalidOperation("updateNode requires targetNodeID and node payload")
                }
                guard let index = nodes.firstIndex(where: { $0.data.id == targetNodeID }) else {
                    continue
                }
                let updatedNode = GraphNodeData(
                    id: targetNodeID,
                    label: node.label,
                    styleClass: node.styleClass,
                    confirmed: node.confirmed,
                    tier: node.tier,
                    tooltip: node.tooltip,
                    isDeactivated: node.isDeactivated,
                    parentIds: node.parentIds,
                    parentId: node.parentId,
                    isExpanded: node.isExpanded
                )
                nodes[index] = GraphNodeElement(data: updatedNode)

            case .removeNode:
                guard let targetNodeID = operation.targetNodeID else {
                    throw GraphPatchApplyError.invalidOperation("removeNode requires targetNodeID")
                }
                nodes.removeAll(where: { $0.data.id == targetNodeID })
                edges.removeAll(where: {
                    $0.data.source == targetNodeID || $0.data.target == targetNodeID
                })

            case .addEdge:
                guard let edge = operation.edge else {
                    throw GraphPatchApplyError.invalidOperation("addEdge requires edge payload")
                }
                let resolvedID = edge.id ?? fallbackEdgeID(edge, existingEdges: edges)
                let newEdge = GraphEdgeElement(
                    data: GraphEdgeData(
                        id: resolvedID,
                        source: edge.source,
                        target: edge.target,
                        label: edge.label,
                        edgeType: edge.edgeType,
                        edgeColor: edge.edgeColor,
                        tooltip: edge.tooltip,
                        strength: edge.strength,
                        isDeactivated: edge.isDeactivated
                    )
                )
                if edges.contains(where: { $0.data.id == resolvedID }) {
                    continue
                }
                edges.append(newEdge)

            case .updateEdge:
                guard let targetEdgeID = operation.targetEdgeID, let edge = operation.edge else {
                    throw GraphPatchApplyError.invalidOperation("updateEdge requires targetEdgeID and edge payload")
                }
                guard let index = edges.firstIndex(where: { $0.data.id == targetEdgeID }) else {
                    continue
                }
                edges[index] = GraphEdgeElement(
                    data: GraphEdgeData(
                        id: targetEdgeID,
                        source: edge.source,
                        target: edge.target,
                        label: edge.label,
                        edgeType: edge.edgeType,
                        edgeColor: edge.edgeColor,
                        tooltip: edge.tooltip,
                        strength: edge.strength,
                        isDeactivated: edge.isDeactivated
                    )
                )

            case .removeEdge:
                guard let targetEdgeID = operation.targetEdgeID else {
                    throw GraphPatchApplyError.invalidOperation("removeEdge requires targetEdgeID")
                }
                edges.removeAll(where: { $0.data.id == targetEdgeID })

            case .updateEdgeStrength:
                guard let targetEdgeID = operation.targetEdgeID else {
                    throw GraphPatchApplyError.invalidOperation("updateEdgeStrength requires targetEdgeID")
                }
                guard let strength = operation.edgeStrength else {
                    throw GraphPatchApplyError.invalidOperation("updateEdgeStrength requires edgeStrength")
                }
                guard let index = edges.firstIndex(where: { $0.data.id == targetEdgeID }) else {
                    continue
                }
                let current = edges[index].data
                edges[index] = GraphEdgeElement(
                    data: GraphEdgeData(
                        id: current.id,
                        source: current.source,
                        target: current.target,
                        label: current.label,
                        edgeType: current.edgeType,
                        edgeColor: current.edgeColor,
                        tooltip: current.tooltip,
                        strength: min(1, max(-1, strength)),
                        isDeactivated: current.isDeactivated
                    )
                )

            case .proposeAlias:
                continue

            case .approveAlias:
                guard let aliasOverride = operation.aliasOverride else {
                    throw GraphPatchApplyError.invalidOperation("approveAlias requires aliasOverride")
                }
                nextAliasOverrides.removeAll(where: { $0.signature == aliasOverride.signature })
                nextAliasOverrides.append(aliasOverride)

            case .rejectAlias:
                continue
            }
        }

        let nextGraphData = CausalGraphData(
            nodes: nodes,
            edges: edges
        )
        let nextVersion = graphVersion(for: nextGraphData)
        let nextDiagram = CustomCausalDiagram(
            graphData: nextGraphData,
            lastModified: ISO8601DateFormatter().string(from: Date()),
            graphVersion: nextVersion,
            baseGraphVersion: diagram.baseGraphVersion ?? diagram.graphVersion
        )

        return GraphPatchApplyResult(
            diagram: nextDiagram,
            aliasOverrides: nextAliasOverrides.sorted { $0.signature < $1.signature }
        )
    }

    private func fallbackEdgeID(_ edge: GraphEdgeData, existingEdges: [GraphEdgeElement]) -> String {
        let prefix = "edge:\(edge.source)|\(edge.target)|\(edge.edgeType ?? "")|\(edge.label ?? "")"
        let maxSuffix = existingEdges
            .compactMap(\ .data.id)
            .filter { $0.hasPrefix(prefix + "#") }
            .compactMap { Int($0.split(separator: "#").last ?? "") }
            .max() ?? -1
        return "\(prefix)#\(maxSuffix + 1)"
    }

    private func graphVersion(for graphData: CausalGraphData) -> String {
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
