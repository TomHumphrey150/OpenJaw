import Foundation

struct PillarNeighborhood: Identifiable, Equatable {
    let pillar: HealthPillar
    let title: String
    let graphData: CausalGraphData
    let interventionNodeIDs: Set<String>

    var id: String {
        pillar.id
    }
}

final class PillarNeighborhoodBuilder {
    private static let cacheQueue = DispatchQueue(label: "PillarNeighborhoodBuilder.cache")
    private static var cache: [String: [PillarNeighborhood]] = [:]

    func build(
        graphData: CausalGraphData,
        inputs: [InputStatus],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        orderedPillars: [HealthPillarDefinition],
        pillarAssignments: [PillarAssignment],
        selectedLensMode: HealthLensMode,
        selectedLensPillars: [HealthPillar],
        selectedLensIsAllSelected: Bool,
        graphVersionHint: String?
    ) -> [PillarNeighborhood] {
        let selectedPillarIDs = Set(selectedLensPillars.map(\.id))
        if selectedLensMode == .pillars && !selectedLensIsAllSelected && selectedPillarIDs.isEmpty {
            return []
        }
        let cacheKey = cacheKeyForBuild(
            graphData: graphData,
            orderedPillars: orderedPillars,
            pillarAssignments: pillarAssignments,
            selectedLensMode: selectedLensMode,
            selectedPillarIDs: selectedPillarIDs,
            selectedLensIsAllSelected: selectedLensIsAllSelected,
            graphVersionHint: graphVersionHint
        )
        if let cached = Self.cacheQueue.sync(execute: { Self.cache[cacheKey] }) {
            return cached
        }

        let nodeIDSet = Set(graphData.nodes.map { $0.data.id })
        var duplicateCounterByBase: [String: Int] = [:]
        let edgeRows = graphData.edges.map { edge in
            let edgeType = edge.data.edgeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = edge.data.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let base = "edge:\(edge.data.source)|\(edge.data.target)|\(edgeType)|\(label)"
            let duplicateIndex = duplicateCounterByBase[base] ?? 0
            duplicateCounterByBase[base] = duplicateIndex + 1
            return EdgeRow(
                id: resolvedEdgeID(edge: edge.data, duplicateIndex: duplicateIndex),
                data: edge.data
            )
        }
        let edgeByID = Dictionary(uniqueKeysWithValues: edgeRows.map { ($0.id, $0.data) })

        var ownedNodeIDsByPillarID: [String: Set<String>] = [:]
        var ownedEdgeIDsByPillarID: [String: Set<String>] = [:]
        var interventionNodeIDsByPillarID: [String: Set<String>] = [:]

        for node in graphData.nodes {
            for pillarID in node.data.pillarIds ?? [] where !pillarID.isEmpty {
                ownedNodeIDsByPillarID[pillarID, default: []].insert(node.data.id)
            }
        }

        for edge in edgeRows {
            for pillarID in edge.data.pillarIds ?? [] where !pillarID.isEmpty {
                ownedEdgeIDsByPillarID[pillarID, default: []].insert(edge.id)
            }
        }

        for assignment in pillarAssignments {
            let pillarID = assignment.pillarId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pillarID.isEmpty else {
                continue
            }

            for nodeID in assignment.graphNodeIds where nodeIDSet.contains(nodeID) {
                ownedNodeIDsByPillarID[pillarID, default: []].insert(nodeID)
            }

            for edgeID in assignment.graphEdgeIds where edgeByID[edgeID] != nil {
                ownedEdgeIDsByPillarID[pillarID, default: []].insert(edgeID)
            }

            for interventionID in assignment.interventionIds {
                guard let input = inputs.first(where: { $0.id == interventionID }) else {
                    continue
                }
                guard let graphNodeID = input.graphNodeID, nodeIDSet.contains(graphNodeID) else {
                    continue
                }
                ownedNodeIDsByPillarID[pillarID, default: []].insert(graphNodeID)
                interventionNodeIDsByPillarID[pillarID, default: []].insert(graphNodeID)
            }
        }

        for input in inputs {
            guard let graphNodeID = input.graphNodeID, !graphNodeID.isEmpty else {
                continue
            }
            guard nodeIDSet.contains(graphNodeID) else {
                continue
            }
            guard let metadata = planningMetadataByInterventionID[input.id], !metadata.pillars.isEmpty else {
                continue
            }

            for pillar in metadata.pillars {
                let pillarID = pillar.id
                interventionNodeIDsByPillarID[pillarID, default: []].insert(graphNodeID)
                ownedNodeIDsByPillarID[pillarID, default: []].insert(graphNodeID)
            }
        }

        for edgeRow in edgeRows {
            for (pillarID, nodeIDs) in ownedNodeIDsByPillarID where nodeIDs.contains(edgeRow.data.source) && nodeIDs.contains(edgeRow.data.target) {
                ownedEdgeIDsByPillarID[pillarID, default: []].insert(edgeRow.id)
            }
        }

        let titleByPillarID = Dictionary(uniqueKeysWithValues: orderedPillars.map { ($0.id.id, $0.title) })
        let rankByPillarID = Dictionary(uniqueKeysWithValues: orderedPillars.enumerated().map { ($1.id.id, $0) })

        var neighborhoods: [PillarNeighborhood] = []
        for definition in orderedPillars {
            let pillarID = definition.id.id
            if selectedLensMode == .pillars
                && !selectedLensIsAllSelected
                && !selectedPillarIDs.contains(pillarID) {
                continue
            }

            let includedNodeIDs = ownedNodeIDsByPillarID[pillarID, default: []]
            let includedEdgeIDs = ownedEdgeIDsByPillarID[pillarID, default: []]
            if includedNodeIDs.isEmpty && !(selectedLensMode == .pillars && !selectedLensIsAllSelected) {
                continue
            }

            let neighborhoodNodes = graphData.nodes.filter { node in
                includedNodeIDs.contains(node.data.id)
            }
            let neighborhoodEdges = edgeRows
                .filter { edgeRow in
                    guard includedNodeIDs.contains(edgeRow.data.source) && includedNodeIDs.contains(edgeRow.data.target) else {
                        return false
                    }
                    return includedEdgeIDs.contains(edgeRow.id)
                }
                .map { GraphEdgeElement(data: $0.data) }

            neighborhoods.append(
                PillarNeighborhood(
                    pillar: definition.id,
                    title: titleByPillarID[pillarID] ?? HealthPillar(id: pillarID).displayName,
                    graphData: CausalGraphData(
                        nodes: neighborhoodNodes,
                        edges: neighborhoodEdges
                    ),
                    interventionNodeIDs: interventionNodeIDsByPillarID[pillarID, default: []]
                )
            )
        }

        neighborhoods.sort { left, right in
            let leftRank = rankByPillarID[left.pillar.id] ?? Int.max
            let rightRank = rankByPillarID[right.pillar.id] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.pillar.id.localizedCaseInsensitiveCompare(right.pillar.id) == .orderedAscending
        }

        let resolvedNeighborhoods: [PillarNeighborhood]
        if selectedLensMode == .pillars && !selectedLensIsAllSelected {
            resolvedNeighborhoods = neighborhoods.filter { selectedPillarIDs.contains($0.pillar.id) }
        } else {
            resolvedNeighborhoods = neighborhoods
        }
        Self.cacheQueue.sync {
            Self.cache[cacheKey] = resolvedNeighborhoods
        }

        return resolvedNeighborhoods
    }

    private func cacheKeyForBuild(
        graphData: CausalGraphData,
        orderedPillars: [HealthPillarDefinition],
        pillarAssignments: [PillarAssignment],
        selectedLensMode: HealthLensMode,
        selectedPillarIDs: Set<String>,
        selectedLensIsAllSelected: Bool,
        graphVersionHint: String?
    ) -> String {
        let versionSegment = graphVersionHint ?? "nodes:\(graphData.nodes.count)-edges:\(graphData.edges.count)"
        let orderedPillarSegment = orderedPillars.map { $0.id.id }.joined(separator: ",")
        let assignmentSegment = pillarAssignments
            .sorted { left, right in
                if left.pillarId != right.pillarId {
                    return left.pillarId.localizedCaseInsensitiveCompare(right.pillarId) == .orderedAscending
                }
                return (left.questionId ?? "").localizedCaseInsensitiveCompare(right.questionId ?? "") == .orderedAscending
            }
            .map { assignment in
                let nodes = assignment.graphNodeIds.sorted().joined(separator: ",")
                let edges = assignment.graphEdgeIds.sorted().joined(separator: ",")
                let interventions = assignment.interventionIds.sorted().joined(separator: ",")
                return "\(assignment.pillarId)|\(assignment.questionId ?? "")|\(nodes)|\(edges)|\(interventions)"
            }
            .joined(separator: ";")
        let selectedSegment = selectedPillarIDs.sorted().joined(separator: ",")
        return "\(versionSegment)#\(selectedLensMode.rawValue)#\(selectedLensIsAllSelected)#\(selectedSegment)#\(orderedPillarSegment)#\(assignmentSegment)"
    }

    private func resolvedEdgeID(edge: GraphEdgeData, duplicateIndex: Int) -> String {
        if let explicitID = edge.id?.trimmingCharacters(in: .whitespacesAndNewlines), !explicitID.isEmpty {
            return explicitID
        }

        let edgeType = edge.edgeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "edge:\(edge.source)|\(edge.target)|\(edgeType)|\(label)#\(duplicateIndex)"
    }

    private struct EdgeRow {
        let id: String
        let data: GraphEdgeData
    }
}
