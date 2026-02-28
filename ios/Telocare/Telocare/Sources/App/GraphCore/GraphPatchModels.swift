import Foundation

enum GraphPatchOperationKind: String, Codable, CaseIterable, Sendable {
    case addNode
    case updateNode
    case removeNode
    case addEdge
    case updateEdge
    case removeEdge
    case updateEdgeStrength
    case proposeAlias
    case approveAlias
    case rejectAlias
}

struct GraphPatchExplanation: Codable, Equatable, Sendable {
    let title: String
    let details: String
}

struct GraphPatchOperation: Codable, Equatable, Sendable {
    let kind: GraphPatchOperationKind
    let targetNodeID: String?
    let targetEdgeID: String?
    let node: GraphNodeData?
    let edge: GraphEdgeData?
    let edgeStrength: Double?
    let aliasProposal: GardenNameProposal?
    let aliasOverride: GardenAliasOverride?

    init(
        kind: GraphPatchOperationKind,
        targetNodeID: String? = nil,
        targetEdgeID: String? = nil,
        node: GraphNodeData? = nil,
        edge: GraphEdgeData? = nil,
        edgeStrength: Double? = nil,
        aliasProposal: GardenNameProposal? = nil,
        aliasOverride: GardenAliasOverride? = nil
    ) {
        self.kind = kind
        self.targetNodeID = targetNodeID
        self.targetEdgeID = targetEdgeID
        self.node = node
        self.edge = edge
        self.edgeStrength = edgeStrength
        self.aliasProposal = aliasProposal
        self.aliasOverride = aliasOverride
    }
}

struct GraphPatchEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: String
    let baseGraphVersion: String
    let operations: [GraphPatchOperation]
    let explanations: [GraphPatchExplanation]
}

struct GraphPatchPreview: Equatable, Sendable {
    let envelope: GraphPatchEnvelope
    let summaryLines: [String]
    let operationCountByKind: [GraphPatchOperationKind: Int]
}

struct GraphPatchConflict: Equatable, Sendable, Identifiable {
    let id: String
    let operationIndex: Int
    let message: String
}

struct GraphPatchRebaseResult: Equatable, Sendable {
    let rebased: GraphPatchEnvelope
    let conflicts: [GraphPatchConflict]
}
