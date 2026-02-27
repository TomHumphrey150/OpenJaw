import Foundation
import Testing
@testable import Telocare

struct GardenHierarchyBuilderTests {
    @Test func dynamicTopLevelClustersBuiltFromAllHabits() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX", pathway: "upstream"),
            makeInput(id: "B_TX", pathway: "midstream"),
            makeInput(id: "C_TX", pathway: "downstream"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX", "C_TX"],
            targetNodes: [("N1", "Stress"), ("N2", "Sleep"), ("N3", "Reflux")],
            edges: [
                ("A_TX", "N1", false),
                ("B_TX", "N2", false),
                ("C_TX", "N3", false),
            ]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: .all
        )

        let level = try #require(result.levels.first)
        #expect(Set(level.clusters.map(\.nodeID)) == Set(["N1", "N2", "N3"]))
    }

    @Test func overlapMembershipIncludesHabitInMultipleSiblingClusters() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX"),
            makeInput(id: "B_TX"),
            makeInput(id: "C_TX"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX", "C_TX"],
            targetNodes: [("N1", "Stress"), ("N2", "GERD"), ("N3", "Sleep")],
            edges: [("A_TX", "N1", false), ("A_TX", "N2", false), ("B_TX", "N2", false), ("C_TX", "N3", false)]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: .all
        )

        let level = try #require(result.levels.first)
        let n1 = try #require(level.clusters.first(where: { $0.nodeID == "N1" }))
        let n2 = try #require(level.clusters.first(where: { $0.nodeID == "N2" }))
        #expect(Set(n1.inputIDs) == Set(["A_TX"]))
        #expect(Set(n2.inputIDs) == Set(["A_TX", "B_TX"]))
    }

    @Test func informativeClusterFilterExcludesClustersCoveringEntireParentSet() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX"),
            makeInput(id: "B_TX"),
            makeInput(id: "C_TX"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX", "C_TX"],
            targetNodes: [("N1", "Stress"), ("ALL", "All Node")],
            edges: [
                ("A_TX", "N1", false),
                ("A_TX", "ALL", false),
                ("B_TX", "ALL", false),
                ("C_TX", "ALL", false),
            ]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: .all
        )

        let level = try #require(result.levels.first)
        #expect(level.clusters.map(\.nodeID) == ["N1"])
    }

    @Test func deterministicOrderingSortsByCoverageThenLabel() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX"),
            makeInput(id: "B_TX"),
            makeInput(id: "C_TX"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX", "C_TX"],
            targetNodes: [("ALPHA", "Alpha"), ("ZETA", "Zeta"), ("HEAVY", "Heavy")],
            edges: [
                ("A_TX", "HEAVY", false),
                ("B_TX", "HEAVY", false),
                ("A_TX", "ALPHA", false),
                ("B_TX", "ZETA", false),
            ]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: .all
        )

        let level = try #require(result.levels.first)
        #expect(level.clusters.map(\.nodeID) == ["HEAVY", "ALPHA", "ZETA"])
    }

    @Test func recursionStopsAtLeafAndTruncatesInvalidPath() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX"),
            makeInput(id: "B_TX"),
            makeInput(id: "C_TX"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX", "C_TX"],
            targetNodes: [("N1", "Stress"), ("N2", "GERD"), ("N3", "Sleep")],
            edges: [
                ("A_TX", "N1", false),
                ("A_TX", "N2", false),
                ("B_TX", "N2", false),
                ("C_TX", "N3", false),
            ]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: GardenHierarchySelection(
                selectedNodePath: ["N2", "N1", "MISSING"]
            )
        )

        #expect(result.resolvedNodePath == ["N2", "N1"])
        #expect(result.filteredInputs.map(\.id) == ["A_TX"])
        let lastLevel = try #require(result.levels.last)
        #expect(lastLevel.clusters.isEmpty)
    }

    @Test func selectedPathNodesAreExcludedFromLaterLevels() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX"),
            makeInput(id: "B_TX"),
            makeInput(id: "C_TX"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX", "C_TX"],
            targetNodes: [("N1", "Stress"), ("N2", "GERD"), ("N3", "Sleep")],
            edges: [
                ("A_TX", "N2", false),
                ("B_TX", "N2", false),
                ("C_TX", "N2", false),
                ("A_TX", "N1", false),
                ("B_TX", "N3", false),
            ]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: GardenHierarchySelection(selectedNodePath: ["N2"])
        )

        let lastLevel = try #require(result.levels.last)
        #expect(lastLevel.clusters.map(\.nodeID).contains("N2") == false)
    }

    @Test func deactivatedEdgesAreExcludedFromCandidates() throws {
        let builder = GardenHierarchyBuilder()
        let inputs = [
            makeInput(id: "A_TX"),
            makeInput(id: "B_TX"),
        ]
        let graphData = makeGraphData(
            interventionIDs: ["A_TX", "B_TX"],
            targetNodes: [("N1", "Stress"), ("N2", "GERD")],
            edges: [
                ("A_TX", "N1", true),
                ("A_TX", "N2", false),
                ("B_TX", "N2", false),
            ]
        )

        let result = builder.build(
            inputs: inputs,
            graphData: graphData,
            selection: .all
        )

        let level = try #require(result.levels.first)
        #expect(level.clusters.map(\.nodeID).contains("N1") == false)
    }

    private func makeInput(id: String, pathway: String? = nil) -> InputStatus {
        InputStatus(
            id: id,
            name: id,
            statusText: "",
            completion: 0,
            isCheckedToday: false,
            graphNodeID: id,
            classificationText: nil,
            isActive: true,
            evidenceLevel: nil,
            evidenceSummary: nil,
            detailedDescription: nil,
            citationIDs: [],
            externalLink: nil,
            causalPathway: pathway
        )
    }

    private func makeGraphData(
        interventionIDs: [String],
        targetNodes: [(id: String, label: String)],
        edges: [(source: String, target: String, isDeactivated: Bool)]
    ) -> CausalGraphData {
        let interventionNodes = interventionIDs.map { interventionID in
            GraphNodeElement(
                data: GraphNodeData(
                    id: interventionID,
                    label: interventionID,
                    styleClass: "intervention",
                    confirmed: nil,
                    tier: nil,
                    tooltip: nil
                )
            )
        }

        let destinationNodes = targetNodes.map { targetNode in
            GraphNodeElement(
                data: GraphNodeData(
                    id: targetNode.id,
                    label: targetNode.label,
                    styleClass: "mechanism",
                    confirmed: nil,
                    tier: nil,
                    tooltip: nil
                )
            )
        }

        let graphEdges = edges.map { edge in
            GraphEdgeElement(
                data: GraphEdgeData(
                    source: edge.source,
                    target: edge.target,
                    label: nil,
                    edgeType: "forward",
                    edgeColor: nil,
                    tooltip: nil,
                    isDeactivated: edge.isDeactivated
                )
            )
        }

        return CausalGraphData(
            nodes: interventionNodes + destinationNodes,
            edges: graphEdges
        )
    }
}
