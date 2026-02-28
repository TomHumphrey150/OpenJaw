import Foundation

protocol GraphPatchRebaser {
    func rebase(_ envelope: GraphPatchEnvelope, onto diagram: CustomCausalDiagram) -> GraphPatchRebaseResult
}

struct DefaultGraphPatchRebaser: GraphPatchRebaser {
    func rebase(_ envelope: GraphPatchEnvelope, onto diagram: CustomCausalDiagram) -> GraphPatchRebaseResult {
        guard envelope.baseGraphVersion != diagram.graphVersion else {
            return GraphPatchRebaseResult(rebased: envelope, conflicts: [])
        }

        var conflicts: [GraphPatchConflict] = []
        for (index, operation) in envelope.operations.enumerated() {
            switch operation.kind {
            case .addNode, .addEdge, .proposeAlias, .approveAlias, .rejectAlias:
                continue
            case .updateNode, .removeNode, .updateEdge, .removeEdge, .updateEdgeStrength:
                conflicts.append(
                    GraphPatchConflict(
                        id: "conflict-\(index)",
                        operationIndex: index,
                        message: "Operation depends on graphVersion \(envelope.baseGraphVersion), current is \(diagram.graphVersion ?? "unknown")."
                    )
                )
            }
        }

        return GraphPatchRebaseResult(
            rebased: GraphPatchEnvelope(
                schemaVersion: envelope.schemaVersion,
                baseGraphVersion: diagram.graphVersion ?? envelope.baseGraphVersion,
                operations: envelope.operations,
                explanations: envelope.explanations
            ),
            conflicts: conflicts
        )
    }
}
