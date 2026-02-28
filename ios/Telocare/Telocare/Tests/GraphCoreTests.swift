import Foundation
import Testing
@testable import Telocare

struct GraphCoreTests {
    @Test func migrationInfersEdgeIDsStrengthsAndGraphVersion() throws {
        let pipeline = DefaultUserDataMigrationPipeline()
        let document = makeDocument(
            customDiagram: CustomCausalDiagram(
                graphData: CausalGraphData(
                    nodes: [
                        GraphNodeElement(
                            data: GraphNodeData(
                                id: "A",
                                label: "A",
                                styleClass: "intervention",
                                confirmed: nil,
                                tier: nil,
                                tooltip: nil
                            )
                        ),
                        GraphNodeElement(
                            data: GraphNodeData(
                                id: "B",
                                label: "B",
                                styleClass: "mechanism",
                                confirmed: "yes",
                                tier: nil,
                                tooltip: GraphTooltip(evidence: "Moderate", stat: nil, citation: nil, mechanism: nil)
                            )
                        ),
                    ],
                    edges: [
                        GraphEdgeElement(
                            data: GraphEdgeData(
                                source: "A",
                                target: "B",
                                label: "causes",
                                edgeType: "forward",
                                edgeColor: nil,
                                tooltip: nil
                            )
                        )
                    ]
                ),
                lastModified: nil,
                graphVersion: nil,
                baseGraphVersion: nil
            ),
            progressQuestionSetState: nil
        )

        let migrated = pipeline.run(
            fetchedDocument: document,
            firstPartyContent: .empty
        ).document

        let migratedDiagram = try #require(migrated.customCausalDiagram)
        let edge = try #require(migratedDiagram.graphData.edges.first?.data)
        #expect(edge.id != nil)
        #expect(edge.strength != nil)
        #expect(migratedDiagram.graphVersion != nil)
        #expect(migrated.progressQuestionSetState != nil)
    }

    @Test func graphPatchValidatorRejectsInvalidStrength() {
        let validator = DefaultGraphPatchValidator()
        let diagram = CustomCausalDiagram(
            graphData: CausalGraphData.defaultGraph,
            lastModified: nil,
            graphVersion: "graph-v1",
            baseGraphVersion: "graph-v1"
        )
        let envelope = GraphPatchEnvelope(
            schemaVersion: "1",
            baseGraphVersion: "graph-v1",
            operations: [
                GraphPatchOperation(
                    kind: .updateEdgeStrength,
                    targetEdgeID: "missing",
                    edgeStrength: 2
                )
            ],
            explanations: []
        )

        let errors = validator.validate(envelope, against: diagram)
        #expect(errors.isEmpty == false)
    }

    @Test func graphPatchApplierUpdatesEdgeStrength() throws {
        let edgeID = "edge:A|B|forward|#0"
        let diagram = CustomCausalDiagram(
            graphData: CausalGraphData(
                nodes: [
                    GraphNodeElement(data: GraphNodeData(id: "A", label: "A", styleClass: "intervention", confirmed: nil, tier: nil, tooltip: nil)),
                    GraphNodeElement(data: GraphNodeData(id: "B", label: "B", styleClass: "mechanism", confirmed: nil, tier: nil, tooltip: nil)),
                ],
                edges: [
                    GraphEdgeElement(
                        data: GraphEdgeData(
                            id: edgeID,
                            source: "A",
                            target: "B",
                            label: nil,
                            edgeType: "forward",
                            edgeColor: nil,
                            tooltip: nil,
                            strength: 0.2
                        )
                    )
                ]
            ),
            lastModified: nil,
            graphVersion: "graph-v1",
            baseGraphVersion: "graph-v1"
        )
        let envelope = GraphPatchEnvelope(
            schemaVersion: "1",
            baseGraphVersion: "graph-v1",
            operations: [
                GraphPatchOperation(
                    kind: .updateEdgeStrength,
                    targetEdgeID: edgeID,
                    edgeStrength: 0.9
                )
            ],
            explanations: []
        )

        let applier = DefaultGraphPatchApplier()
        let result = try applier.apply(envelope, to: diagram, aliasOverrides: [])
        let updated = try #require(result.diagram.graphData.edges.first?.data)
        #expect(updated.strength == 0.9)
    }

    @Test func graphPatchRebaserFlagsVersionConflicts() {
        let rebaser = DefaultGraphPatchRebaser()
        let envelope = GraphPatchEnvelope(
            schemaVersion: "1",
            baseGraphVersion: "graph-old",
            operations: [
                GraphPatchOperation(kind: .updateNode, targetNodeID: "A", node: GraphNodeData(id: "A", label: "A", styleClass: "mechanism", confirmed: nil, tier: nil, tooltip: nil))
            ],
            explanations: []
        )
        let diagram = CustomCausalDiagram(
            graphData: CausalGraphData.defaultGraph,
            lastModified: nil,
            graphVersion: "graph-new",
            baseGraphVersion: "graph-new"
        )

        let result = rebaser.rebase(envelope, onto: diagram)
        #expect(result.conflicts.count == 1)
        #expect(result.rebased.baseGraphVersion == "graph-new")
    }

    private func makeDocument(
        customDiagram: CustomCausalDiagram?,
        progressQuestionSetState: ProgressQuestionSetState?
    ) -> UserDataDocument {
        UserDataDocument(
            version: 1,
            lastExport: nil,
            personalStudies: [],
            notes: [],
            experiments: [],
            interventionRatings: [],
            dailyCheckIns: [:],
            dailyDoseProgress: [:],
            interventionCompletionEvents: [],
            interventionDoseSettings: [:],
            appleHealthConnections: [:],
            nightExposures: [],
            nightOutcomes: [],
            morningStates: [],
            morningQuestionnaire: nil,
            progressQuestionSetState: progressQuestionSetState,
            wakeDaySleepAttributionMigrated: false,
            habitTrials: [],
            habitClassifications: [],
            activeInterventions: [],
            hiddenInterventions: [],
            unlockedAchievements: [],
            customCausalDiagram: customDiagram,
            gardenAliasOverrides: [],
            experienceFlow: .empty
        )
    }
}
