import Foundation

struct GraphCheckpoint: Equatable, Sendable, Identifiable {
    let id: String
    let graphVersion: String
    let createdAt: String
    let diagram: CustomCausalDiagram
}

enum GraphConflictResolutionChoice: Sendable, Equatable, Hashable {
    case server
    case local
}

struct GraphPatchPreviewResult: Equatable, Sendable {
    let preview: GraphPatchPreview
    let conflicts: [GraphPatchConflict]
}

enum GraphKernelError: Error {
    case validationFailed([String])
    case unresolvedConflicts([GraphPatchConflict])
}

actor GraphKernel {
    private var diagram: CustomCausalDiagram
    private var aliasOverrides: [GardenAliasOverride]
    private var checkpoints: [GraphCheckpoint]

    private let validator: GraphPatchValidator
    private let applier: GraphPatchApplier
    private let rebaser: GraphPatchRebaser

    init(
        diagram: CustomCausalDiagram,
        aliasOverrides: [GardenAliasOverride] = [],
        validator: GraphPatchValidator = DefaultGraphPatchValidator(),
        applier: GraphPatchApplier = DefaultGraphPatchApplier(),
        rebaser: GraphPatchRebaser = DefaultGraphPatchRebaser()
    ) {
        self.diagram = diagram
        self.aliasOverrides = aliasOverrides
        self.validator = validator
        self.applier = applier
        self.rebaser = rebaser
        checkpoints = []
    }

    func currentDiagram() -> CustomCausalDiagram {
        diagram
    }

    func currentAliasOverrides() -> [GardenAliasOverride] {
        aliasOverrides
    }

    func checkpointHistory() -> [GraphCheckpoint] {
        checkpoints.sorted { $0.createdAt > $1.createdAt }
    }

    func checkpoint(for graphVersion: String) -> GraphCheckpoint? {
        checkpoints.first { $0.graphVersion == graphVersion }
    }

    func replaceGraphData(_ graphData: CausalGraphData, lastModified: String? = nil) {
        let nextVersion = graphVersion(for: graphData)
        diagram = CustomCausalDiagram(
            graphData: graphData,
            lastModified: lastModified ?? ISO8601DateFormatter().string(from: Date()),
            graphVersion: nextVersion,
            baseGraphVersion: diagram.baseGraphVersion ?? diagram.graphVersion ?? nextVersion
        )
    }

    func replace(
        diagram: CustomCausalDiagram,
        aliasOverrides: [GardenAliasOverride],
        recordCheckpoint: Bool
    ) {
        self.diagram = diagram
        self.aliasOverrides = aliasOverrides.sorted { $0.signature < $1.signature }
        guard recordCheckpoint else {
            return
        }
        let version = diagram.graphVersion ?? "graph-unknown"
        checkpoints.append(
            GraphCheckpoint(
                id: "checkpoint-\(version)-\(checkpoints.count + 1)",
                graphVersion: version,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                diagram: diagram
            )
        )
    }

    func preview(_ envelope: GraphPatchEnvelope) throws -> GraphPatchPreviewResult {
        let validationErrors = validator.validate(envelope, against: diagram)
        if !validationErrors.isEmpty {
            throw GraphKernelError.validationFailed(validationErrors)
        }

        let rebase = rebaser.rebase(envelope, onto: diagram)
        let countByKind = rebase.rebased.operations.reduce(into: [GraphPatchOperationKind: Int]()) { partialResult, operation in
            partialResult[operation.kind, default: 0] += 1
        }
        let summaryLines = countByKind
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { key, count in "\(count)x \(key.rawValue)" }

        return GraphPatchPreviewResult(
            preview: GraphPatchPreview(
                envelope: rebase.rebased,
                summaryLines: summaryLines,
                operationCountByKind: countByKind
            ),
            conflicts: rebase.conflicts
        )
    }

    func apply(
        _ envelope: GraphPatchEnvelope,
        conflictResolutions: [Int: GraphConflictResolutionChoice] = [:]
    ) throws -> GraphPatchApplyResult {
        let previewResult = try preview(envelope)
        let conflictIndices = Set(previewResult.conflicts.map(\ .operationIndex))
        let unresolvedConflictIndices = conflictIndices.subtracting(conflictResolutions.keys)
        if !unresolvedConflictIndices.isEmpty {
            let unresolved = previewResult.conflicts.filter { unresolvedConflictIndices.contains($0.operationIndex) }
            throw GraphKernelError.unresolvedConflicts(unresolved)
        }

        let operations = previewResult.preview.envelope.operations.enumerated().compactMap { index, operation -> GraphPatchOperation? in
            guard let choice = conflictResolutions[index] else {
                return operation
            }

            switch choice {
            case .local:
                return operation
            case .server:
                return nil
            }
        }

        let resolvedEnvelope = GraphPatchEnvelope(
            schemaVersion: previewResult.preview.envelope.schemaVersion,
            baseGraphVersion: previewResult.preview.envelope.baseGraphVersion,
            operations: operations,
            explanations: previewResult.preview.envelope.explanations
        )

        let applied = try applier.apply(
            resolvedEnvelope,
            to: diagram,
            aliasOverrides: aliasOverrides
        )
        diagram = applied.diagram
        aliasOverrides = applied.aliasOverrides

        let version = applied.diagram.graphVersion ?? "graph-unknown"
        let checkpoint = GraphCheckpoint(
            id: "checkpoint-\(version)-\(checkpoints.count + 1)",
            graphVersion: version,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            diagram: applied.diagram
        )
        checkpoints.append(checkpoint)

        return applied
    }

    @discardableResult
    func rollback(to graphVersion: String) -> CustomCausalDiagram? {
        guard let checkpoint = checkpoints.last(where: { $0.graphVersion == graphVersion }) else {
            return nil
        }

        diagram = checkpoint.diagram
        return diagram
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
