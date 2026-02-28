import Foundation

protocol GraphPatchValidator {
    func validate(_ envelope: GraphPatchEnvelope, against diagram: CustomCausalDiagram) -> [String]
}

struct DefaultGraphPatchValidator: GraphPatchValidator {
    func validate(_ envelope: GraphPatchEnvelope, against diagram: CustomCausalDiagram) -> [String] {
        var errors: [String] = []

        if envelope.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("schemaVersion is required.")
        }

        if envelope.baseGraphVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("baseGraphVersion is required.")
        }

        if envelope.operations.isEmpty {
            errors.append("At least one patch operation is required.")
        }

        let nodeIDs = Set(diagram.graphData.nodes.map(\ .data.id))
        let edgeIDs = Set(diagram.graphData.edges.compactMap(\ .data.id))

        for (index, operation) in envelope.operations.enumerated() {
            let prefix = "Operation \(index + 1) [\(operation.kind.rawValue)]"
            switch operation.kind {
            case .addNode:
                guard let node = operation.node else {
                    errors.append("\(prefix): node payload is required.")
                    continue
                }
                if nodeIDs.contains(node.id) {
                    errors.append("\(prefix): node \(node.id) already exists.")
                }

            case .updateNode:
                guard let targetNodeID = operation.targetNodeID else {
                    errors.append("\(prefix): targetNodeID is required.")
                    continue
                }
                if !nodeIDs.contains(targetNodeID) {
                    errors.append("\(prefix): target node \(targetNodeID) not found.")
                }
                guard operation.node != nil else {
                    errors.append("\(prefix): node payload is required.")
                    continue
                }

            case .removeNode:
                guard let targetNodeID = operation.targetNodeID else {
                    errors.append("\(prefix): targetNodeID is required.")
                    continue
                }
                if !nodeIDs.contains(targetNodeID) {
                    errors.append("\(prefix): target node \(targetNodeID) not found.")
                }

            case .addEdge:
                guard let edge = operation.edge else {
                    errors.append("\(prefix): edge payload is required.")
                    continue
                }
                if let edgeID = edge.id, edgeIDs.contains(edgeID) {
                    errors.append("\(prefix): edge \(edgeID) already exists.")
                }
                if !nodeIDs.contains(edge.source) || !nodeIDs.contains(edge.target) {
                    errors.append("\(prefix): source/target nodes must exist.")
                }

            case .updateEdge:
                guard let targetEdgeID = operation.targetEdgeID else {
                    errors.append("\(prefix): targetEdgeID is required.")
                    continue
                }
                if !edgeIDs.contains(targetEdgeID) {
                    errors.append("\(prefix): target edge \(targetEdgeID) not found.")
                }
                guard operation.edge != nil else {
                    errors.append("\(prefix): edge payload is required.")
                    continue
                }

            case .removeEdge:
                guard let targetEdgeID = operation.targetEdgeID else {
                    errors.append("\(prefix): targetEdgeID is required.")
                    continue
                }
                if !edgeIDs.contains(targetEdgeID) {
                    errors.append("\(prefix): target edge \(targetEdgeID) not found.")
                }

            case .updateEdgeStrength:
                guard let targetEdgeID = operation.targetEdgeID else {
                    errors.append("\(prefix): targetEdgeID is required.")
                    continue
                }
                if !edgeIDs.contains(targetEdgeID) {
                    errors.append("\(prefix): target edge \(targetEdgeID) not found.")
                }
                guard let strength = operation.edgeStrength else {
                    errors.append("\(prefix): edgeStrength is required.")
                    continue
                }
                if strength < -1 || strength > 1 {
                    errors.append("\(prefix): edgeStrength must be in [-1, 1].")
                }

            case .proposeAlias:
                guard operation.aliasProposal != nil else {
                    errors.append("\(prefix): aliasProposal is required.")
                    continue
                }

            case .approveAlias:
                guard operation.aliasOverride != nil else {
                    errors.append("\(prefix): aliasOverride is required.")
                    continue
                }

            case .rejectAlias:
                guard operation.aliasProposal != nil else {
                    errors.append("\(prefix): aliasProposal is required.")
                    continue
                }
            }
        }

        return errors
    }
}
