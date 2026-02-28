import Foundation
import Testing
@testable import Telocare

struct GraphClusterCLITests {
    @Test func generateHierarchyReportFromFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        let configPath = environment["TELOCARE_CLUSTER_CONFIG_PATH"] ?? "/tmp/telocare-cluster-config.json"
        guard FileManager.default.fileExists(atPath: configPath) else {
            return
        }
        let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let config = try JSONDecoder().decode(GraphClusterCLIConfig.self, from: configData)
        let maxDepth = max(1, config.maxDepth)

        let rowObject = try Self.readJSONObject(atPath: config.inputPath)
        let catalogObject = try Self.readJSONObject(atPath: config.catalogPath)

        let userID = rowObject["user_id"] as? String ?? "(unknown)"
        let updatedAt = rowObject["updated_at"] as? String

        let storeObject = try #require(rowObject["data"])
        let storeData = try JSONSerialization.data(withJSONObject: storeObject, options: [])
        let document = try JSONDecoder().decode(UserDataDocument.self, from: storeData)

        let catalogPayload = try #require(catalogObject["data"])
        let catalogData = try JSONSerialization.data(withJSONObject: catalogPayload, options: [])
        let interventionsCatalog = try JSONDecoder().decode(InterventionsCatalog.self, from: catalogData)

        let firstPartyContent = FirstPartyContentBundle(
            graphData: nil,
            interventionsCatalog: interventionsCatalog,
            outcomesMetadata: .empty,
            foundationCatalog: nil,
            planningPolicy: nil
        )

        let snapshot = DashboardSnapshotBuilder().build(
            from: document,
            firstPartyContent: firstPartyContent
        )

        let graphData = document.customCausalDiagram?.graphData ?? CanonicalGraphLoader.loadGraphOrFallback()
        let builder = GardenHierarchyBuilder()
        let inputNameByID = Dictionary(uniqueKeysWithValues: snapshot.inputs.map { ($0.id, $0.name) })
        let graphNodeByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data) })
        let graphEdgeByID: [String: GraphEdgeData] = Dictionary(
            uniqueKeysWithValues: graphData.edges.compactMap { edge in
                guard let edgeID = edge.data.id else {
                    return nil
                }
                return (edgeID, edge.data)
            }
        )
        let outgoingEdgesBySourceNodeID = Dictionary(grouping: graphData.edges.map(\.data), by: \.source)
        let progressQuestionProposalBuilder = ProgressQuestionProposalBuilder()
        let planningMetadataByInterventionID = HabitPlanningMetadataResolver().metadataByInterventionID(for: snapshot.inputs)
        let graphVersion = document.customCausalDiagram?.graphVersion ?? "graph-unknown"

        let topLevelClusters = Self.buildClusterTree(
            inputs: snapshot.inputs,
            graphData: graphData,
            builder: builder,
            path: [],
            maxDepth: maxDepth,
            inputNameByID: inputNameByID
        )
        let clusterPathIndex = Self.buildClusterPathIndex(from: topLevelClusters)

        let unresolvedActiveInputs = snapshot.inputs
            .filter(\.isActive)
            .compactMap { input -> UnresolvedInputReport? in
                let sourceNodeID = input.graphNodeID ?? input.id

                guard let sourceNode = graphNodeByID[sourceNodeID] else {
                    return UnresolvedInputReport(
                        inputID: input.id,
                        inputName: input.name,
                        sourceNodeID: sourceNodeID,
                        reason: "missing_graph_node"
                    )
                }

                if sourceNode.isDeactivated == true {
                    return UnresolvedInputReport(
                        inputID: input.id,
                        inputName: input.name,
                        sourceNodeID: sourceNodeID,
                        reason: "source_node_deactivated"
                    )
                }

                return nil
            }

        let habitMappings = snapshot.inputs.map { input in
            let sourceNodeID = input.graphNodeID ?? input.id
            let sourceNode = graphNodeByID[sourceNodeID]
            let outgoingEdges = outgoingEdgesBySourceNodeID[sourceNodeID] ?? []
            let deactivatedOutgoingEdges = outgoingEdges.filter { $0.isDeactivated == true }
            let activeOutgoingEdges = outgoingEdges.filter { $0.isDeactivated != true }
            let activeTargetEdgesForClustering = activeOutgoingEdges.filter { edge in
                guard let targetNode = graphNodeByID[edge.target] else {
                    return false
                }
                return targetNode.styleClass != "intervention" && targetNode.isDeactivated != true
            }

            return HabitGraphAttachmentReport(
                inputID: input.id,
                inputName: input.name,
                isActive: input.isActive,
                sourceNodeID: sourceNodeID,
                sourceNodeExists: sourceNode != nil,
                sourceNodeStyleClass: sourceNode?.styleClass,
                sourceNodeIsDeactivated: sourceNode?.isDeactivated ?? false,
                attachedNodeIDs: Array(Set(activeTargetEdgesForClustering.map(\.target))).sorted(),
                attachedEdgeIDs: Array(Set(activeTargetEdgesForClustering.compactMap(\.id))).sorted(),
                allOutgoingEdgeIDs: Array(Set(outgoingEdges.compactMap(\.id))).sorted(),
                deactivatedOutgoingEdgeIDs: Array(Set(deactivatedOutgoingEdges.compactMap(\.id))).sorted(),
                clusterPaths: clusterPathIndex.inputIDToPaths[input.id] ?? []
            )
        }

        let questionProposal = progressQuestionProposalBuilder.build(
            graphData: graphData,
            inputs: snapshot.inputs,
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            mode: .baseline,
            graphVersion: graphVersion,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let outcomeQuestionMappings = questionProposal.questions.map { question in
            let questionClusterPaths = question.sourceNodeIDs
                .flatMap { clusterPathIndex.nodeIDToPaths[$0] ?? [] }
            let uniqueClusterPaths = Array(Set(questionClusterPaths)).sorted()
            let missingNodeIDs = question.sourceNodeIDs.filter { graphNodeByID[$0] == nil }
            let missingEdgeIDs = question.sourceEdgeIDs.filter { graphEdgeByID[$0] == nil }

            return OutcomeQuestionGraphAttachmentReport(
                questionID: question.id,
                title: question.title,
                sourceNodeIDs: question.sourceNodeIDs,
                sourceEdgeIDs: question.sourceEdgeIDs,
                missingNodeIDs: missingNodeIDs,
                missingEdgeIDs: missingEdgeIDs,
                clusterPaths: uniqueClusterPaths
            )
        }

        let edgeCoverageEntries = Self.buildEdgeCoverageEntries(
            habitMappings: habitMappings,
            outcomeQuestionMappings: outcomeQuestionMappings,
            graphEdgeByID: graphEdgeByID,
            clusterTreeNodeIDSet: Set(clusterPathIndex.clusterNodeIDs)
        )
        let uncoveredEdgeIDs = Array(
            Set(
                edgeCoverageEntries
                    .filter { !$0.targetInClusterTree && !$0.sourceInClusterTree }
                    .map { $0.edgeID }
            )
        ).sorted()

        let report = GraphClusterCLIReport(
            userID: userID,
            rowUpdatedAt: updatedAt,
            graphVersion: document.customCausalDiagram?.graphVersion,
            graphNodeCount: graphData.nodes.count,
            graphEdgeCount: graphData.edges.count,
            activeInputCount: snapshot.inputs.filter(\.isActive).count,
            topLevelClusterCount: topLevelClusters.count,
            maxDepthEvaluated: maxDepth,
            unresolvedActiveInputs: unresolvedActiveInputs,
            habitMappings: habitMappings,
            outcomeQuestionMappings: outcomeQuestionMappings,
            edgeCoverage: ClusterTreeEdgeCoverageReport(
                clusterTreeNodeIDs: clusterPathIndex.clusterNodeIDs,
                referencedEdgeCount: edgeCoverageEntries.count,
                coveredEdgeCount: edgeCoverageEntries.filter { $0.targetInClusterTree || $0.sourceInClusterTree }.count,
                uncoveredEdgeCount: edgeCoverageEntries.filter { !$0.targetInClusterTree && !$0.sourceInClusterTree }.count,
                uncoveredEdgeIDs: uncoveredEdgeIDs,
                entries: edgeCoverageEntries
            ),
            topLevelClusters: topLevelClusters,
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputData = try encoder.encode(report)
        try outputData.write(to: URL(fileURLWithPath: config.reportPath), options: Data.WritingOptions.atomic)

        print("Graph cluster report generated for user \(userID)")
        print("Top-level clusters: \(topLevelClusters.count)")
        if !unresolvedActiveInputs.isEmpty {
            print("Unresolved active inputs: \(unresolvedActiveInputs.count)")
        }
        let habitsWithoutClusterCoverage = habitMappings.filter { $0.clusterPaths.isEmpty }
        if !habitsWithoutClusterCoverage.isEmpty {
            print("Habits without cluster path coverage: \(habitsWithoutClusterCoverage.count)")
        }
        let outcomeQuestionsWithoutClusterCoverage = outcomeQuestionMappings.filter { $0.clusterPaths.isEmpty }
        if !outcomeQuestionsWithoutClusterCoverage.isEmpty {
            print("Outcome questions without cluster path coverage: \(outcomeQuestionsWithoutClusterCoverage.count)")
        }
        if !uncoveredEdgeIDs.isEmpty {
            print("Referenced edges outside cluster tree: \(uncoveredEdgeIDs.count)")
        }
        print("Output: \(config.reportPath)")
    }

    private static func buildClusterTree(
        inputs: [InputStatus],
        graphData: CausalGraphData,
        builder: GardenHierarchyBuilder,
        path: [String],
        maxDepth: Int,
        inputNameByID: [String: String]
    ) -> [ClusterNodeReport] {
        if path.count >= maxDepth {
            return []
        }

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: GardenHierarchySelection(selectedNodePath: path)
        )

        guard let currentLevel = result.levels.last else {
            return []
        }

        return currentLevel.clusters.map { cluster in
            let children = buildClusterTree(
                inputs: inputs,
                graphData: graphData,
                builder: builder,
                path: path + [cluster.nodeID],
                maxDepth: maxDepth,
                inputNameByID: inputNameByID
            )

            let memberNames = cluster.inputIDs.map { inputNameByID[$0] ?? $0 }

            return ClusterNodeReport(
                id: cluster.nodeID,
                title: cluster.title,
                nodeIDs: cluster.nodeIDs,
                memberCount: cluster.inputIDs.count,
                members: cluster.inputIDs,
                memberNames: memberNames,
                children: children
            )
        }
    }

    private static func buildClusterPathIndex(from clusters: [ClusterNodeReport]) -> ClusterPathIndex {
        var nodeIDToPaths: [String: Set<String>] = [:]
        var inputIDToPaths: [String: Set<String>] = [:]
        var clusterNodeIDSet = Set<String>()

        func visit(node: ClusterNodeReport, pathTitles: [String]) {
            let nextPathTitles = pathTitles + [node.title]
            let path = nextPathTitles.joined(separator: " > ")

            for nodeID in node.nodeIDs {
                nodeIDToPaths[nodeID, default: []].insert(path)
                clusterNodeIDSet.insert(nodeID)
            }

            for inputID in node.members {
                inputIDToPaths[inputID, default: []].insert(path)
            }

            for child in node.children {
                visit(node: child, pathTitles: nextPathTitles)
            }
        }

        for cluster in clusters {
            visit(node: cluster, pathTitles: [])
        }

        let sortedNodeIDToPaths = nodeIDToPaths.mapValues { Array($0).sorted() }
        let sortedInputIDToPaths = inputIDToPaths.mapValues { Array($0).sorted() }
        return ClusterPathIndex(
            nodeIDToPaths: sortedNodeIDToPaths,
            inputIDToPaths: sortedInputIDToPaths,
            clusterNodeIDs: Array(clusterNodeIDSet).sorted()
        )
    }

    private static func buildEdgeCoverageEntries(
        habitMappings: [HabitGraphAttachmentReport],
        outcomeQuestionMappings: [OutcomeQuestionGraphAttachmentReport],
        graphEdgeByID: [String: GraphEdgeData],
        clusterTreeNodeIDSet: Set<String>
    ) -> [ClusterTreeEdgeCoverageEntry] {
        var entries: [ClusterTreeEdgeCoverageEntry] = []

        for habit in habitMappings {
            for edgeID in habit.attachedEdgeIDs {
                entries.append(
                    edgeCoverageEntry(
                        edgeID: edgeID,
                        referenceType: "habit",
                        referenceID: habit.inputID,
                        graphEdgeByID: graphEdgeByID,
                        clusterTreeNodeIDSet: clusterTreeNodeIDSet
                    )
                )
            }
        }

        for question in outcomeQuestionMappings {
            for edgeID in question.sourceEdgeIDs {
                entries.append(
                    edgeCoverageEntry(
                        edgeID: edgeID,
                        referenceType: "outcome_question",
                        referenceID: question.questionID,
                        graphEdgeByID: graphEdgeByID,
                        clusterTreeNodeIDSet: clusterTreeNodeIDSet
                    )
                )
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.referenceType != rhs.referenceType {
                return lhs.referenceType < rhs.referenceType
            }
            if lhs.referenceID != rhs.referenceID {
                return lhs.referenceID < rhs.referenceID
            }
            return lhs.edgeID < rhs.edgeID
        }
    }

    private static func edgeCoverageEntry(
        edgeID: String,
        referenceType: String,
        referenceID: String,
        graphEdgeByID: [String: GraphEdgeData],
        clusterTreeNodeIDSet: Set<String>
    ) -> ClusterTreeEdgeCoverageEntry {
        let edge = graphEdgeByID[edgeID]
        let sourceNodeID = edge?.source
        let targetNodeID = edge?.target
        let sourceInClusterTree = sourceNodeID.map { clusterTreeNodeIDSet.contains($0) } ?? false
        let targetInClusterTree = targetNodeID.map { clusterTreeNodeIDSet.contains($0) } ?? false

        return ClusterTreeEdgeCoverageEntry(
            edgeID: edgeID,
            referenceType: referenceType,
            referenceID: referenceID,
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            edgeExists: edge != nil,
            edgeIsDeactivated: edge?.isDeactivated,
            sourceInClusterTree: sourceInClusterTree,
            targetInClusterTree: targetInClusterTree
        )
    }

    private static func readJSONObject(atPath path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try #require(raw as? [String: Any])
    }
}

private struct GraphClusterCLIReport: Codable {
    let userID: String
    let rowUpdatedAt: String?
    let graphVersion: String?
    let graphNodeCount: Int
    let graphEdgeCount: Int
    let activeInputCount: Int
    let topLevelClusterCount: Int
    let maxDepthEvaluated: Int
    let unresolvedActiveInputs: [UnresolvedInputReport]
    let habitMappings: [HabitGraphAttachmentReport]
    let outcomeQuestionMappings: [OutcomeQuestionGraphAttachmentReport]
    let edgeCoverage: ClusterTreeEdgeCoverageReport
    let topLevelClusters: [ClusterNodeReport]
    let generatedAt: String
}

private struct GraphClusterCLIConfig: Codable {
    let inputPath: String
    let catalogPath: String
    let reportPath: String
    let maxDepth: Int
}

private struct UnresolvedInputReport: Codable {
    let inputID: String
    let inputName: String
    let sourceNodeID: String
    let reason: String
}

private struct HabitGraphAttachmentReport: Codable {
    let inputID: String
    let inputName: String
    let isActive: Bool
    let sourceNodeID: String
    let sourceNodeExists: Bool
    let sourceNodeStyleClass: String?
    let sourceNodeIsDeactivated: Bool
    let attachedNodeIDs: [String]
    let attachedEdgeIDs: [String]
    let allOutgoingEdgeIDs: [String]
    let deactivatedOutgoingEdgeIDs: [String]
    let clusterPaths: [String]
}

private struct OutcomeQuestionGraphAttachmentReport: Codable {
    let questionID: String
    let title: String
    let sourceNodeIDs: [String]
    let sourceEdgeIDs: [String]
    let missingNodeIDs: [String]
    let missingEdgeIDs: [String]
    let clusterPaths: [String]
}

private struct ClusterPathIndex {
    let nodeIDToPaths: [String: [String]]
    let inputIDToPaths: [String: [String]]
    let clusterNodeIDs: [String]
}

private struct ClusterTreeEdgeCoverageReport: Codable {
    let clusterTreeNodeIDs: [String]
    let referencedEdgeCount: Int
    let coveredEdgeCount: Int
    let uncoveredEdgeCount: Int
    let uncoveredEdgeIDs: [String]
    let entries: [ClusterTreeEdgeCoverageEntry]
}

private struct ClusterTreeEdgeCoverageEntry: Codable {
    let edgeID: String
    let referenceType: String
    let referenceID: String
    let sourceNodeID: String?
    let targetNodeID: String?
    let edgeExists: Bool
    let edgeIsDeactivated: Bool?
    let sourceInClusterTree: Bool
    let targetInClusterTree: Bool
}

private struct ClusterNodeReport: Codable {
    let id: String
    let title: String
    let nodeIDs: [String]
    let memberCount: Int
    let members: [String]
    let memberNames: [String]
    let children: [ClusterNodeReport]
}
