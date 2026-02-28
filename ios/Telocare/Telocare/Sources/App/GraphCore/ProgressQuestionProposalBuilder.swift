import Foundation

struct ProgressQuestionProposalBuilder {
    private let maximumQuestionCount: Int

    init(maximumQuestionCount: Int = 6) {
        self.maximumQuestionCount = max(1, maximumQuestionCount)
    }

    func build(
        graphData: CausalGraphData,
        inputs: [InputStatus] = [],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata] = [:],
        policy: PlanningPolicy = .default,
        mode: PlanningMode = .baseline,
        graphVersion: String,
        createdAt: String
    ) -> ProgressQuestionSetProposal {
        let nodeByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data) })
        let activeInputs = inputs.filter(\.isActive)
        let foundationNodeIDs = resolvedFoundationNodeIDs(
            activeInputs: activeInputs,
            metadataByInterventionID: planningMetadataByInterventionID,
            policy: policy,
            nodeByID: nodeByID
        )
        let acuteNodeIDs = resolvedAcuteNodeIDs(
            activeInputs: activeInputs,
            graphData: graphData,
            metadataByInterventionID: planningMetadataByInterventionID,
            nodeByID: nodeByID
        )

        let foundationBudget = max(2, maximumQuestionCount / 2)
        let acuteBudget = max(1, maximumQuestionCount - foundationBudget)
        var selectedNodeIDs: [String] = []
        selectedNodeIDs.append(contentsOf: foundationNodeIDs.prefix(foundationBudget))

        let orderedAcuteNodeIDs: [String]
        if mode == .flare {
            orderedAcuteNodeIDs = acuteNodeIDs
        } else {
            orderedAcuteNodeIDs = acuteNodeIDs.sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }
        for nodeID in orderedAcuteNodeIDs where selectedNodeIDs.count < foundationBudget + acuteBudget {
            if !selectedNodeIDs.contains(nodeID) {
                selectedNodeIDs.append(nodeID)
            }
        }

        if selectedNodeIDs.count < maximumQuestionCount {
            let fallbackNodes = graphData.nodes
                .map(\.data)
                .filter { node in
                    node.isDeactivated != true
                        && node.styleClass.localizedCaseInsensitiveContains("intervention") == false
                }
                .sorted(by: compareNodesForFallback)
            for node in fallbackNodes where selectedNodeIDs.count < maximumQuestionCount {
                if !selectedNodeIDs.contains(node.id) {
                    selectedNodeIDs.append(node.id)
                }
            }
        }

        if selectedNodeIDs.isEmpty {
            selectedNodeIDs = graphData.nodes.map(\.data.id).sorted().prefix(maximumQuestionCount).map { $0 }
        }

        let questions: [GraphDerivedProgressQuestion] = selectedNodeIDs.compactMap { nodeID in
            guard let node = nodeByID[nodeID] else {
                return nil
            }
            return GraphDerivedProgressQuestion(
                id: "progress.\(node.id.lowercased())",
                title: "How is \(firstLine(in: node.label)) today?",
                sourceNodeIDs: [node.id],
                sourceEdgeIDs: associatedEdgeIDs(for: node.id, in: graphData)
            )
        }

        return ProgressQuestionSetProposal(
            sourceGraphVersion: graphVersion,
            proposedQuestionSetVersion: "questions-\(graphVersion)",
            questions: questions,
            createdAt: createdAt
        )
    }

    private func resolvedFoundationNodeIDs(
        activeInputs: [InputStatus],
        metadataByInterventionID: [String: HabitPlanningMetadata],
        policy: PlanningPolicy,
        nodeByID: [String: GraphNodeData]
    ) -> [String] {
        var rows: [(nodeID: String, rank: Int)] = []
        for input in activeInputs {
            guard let metadata = metadataByInterventionID[input.id] else {
                continue
            }
            guard metadata.tags.contains(.foundation) else {
                continue
            }
            let rank = metadata.pillars.map { policy.rank(for: $0) }.min() ?? (policy.pillarOrder.count + 1)
            for nodeID in metadata.acuteTargetNodeIDs where nodeByID[nodeID] != nil {
                rows.append((nodeID: nodeID, rank: rank))
            }
        }

        var seen = Set<String>()
        return rows
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return lhs.nodeID < rhs.nodeID
            }
            .compactMap { row in
                if seen.insert(row.nodeID).inserted {
                    return row.nodeID
                }
                return nil
            }
    }

    private func resolvedAcuteNodeIDs(
        activeInputs: [InputStatus],
        graphData: CausalGraphData,
        metadataByInterventionID: [String: HabitPlanningMetadata],
        nodeByID: [String: GraphNodeData]
    ) -> [String] {
        let hierarchy = GardenHierarchyBuilder().build(
            inputs: activeInputs,
            graphData: graphData,
            selection: .all
        )
        var orderedNodeIDs: [String] = []
        for cluster in hierarchy.levels.first?.clusters ?? [] {
            for nodeID in cluster.nodeIDs where nodeByID[nodeID] != nil {
                if !orderedNodeIDs.contains(nodeID) {
                    orderedNodeIDs.append(nodeID)
                }
            }
        }

        for input in activeInputs {
            guard let metadata = metadataByInterventionID[input.id] else {
                continue
            }
            guard metadata.tags.contains(.acute) else {
                continue
            }
            for nodeID in metadata.acuteTargetNodeIDs where nodeByID[nodeID] != nil {
                if !orderedNodeIDs.contains(nodeID) {
                    orderedNodeIDs.append(nodeID)
                }
            }
        }

        return orderedNodeIDs
    }

    private func compareNodesForFallback(_ lhs: GraphNodeData, _ rhs: GraphNodeData) -> Bool {
        let lhsTitle = firstLine(in: lhs.label)
        let rhsTitle = firstLine(in: rhs.label)
        if lhsTitle != rhsTitle {
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func associatedEdgeIDs(for nodeID: String, in graphData: CausalGraphData) -> [String] {
        graphData.edges
            .compactMap { edge in
                guard edge.data.source == nodeID || edge.data.target == nodeID else {
                    return nil
                }
                return edge.data.id
            }
            .sorted()
    }

    private func firstLine(in label: String) -> String {
        label.components(separatedBy: "\n").first ?? label
    }
}
