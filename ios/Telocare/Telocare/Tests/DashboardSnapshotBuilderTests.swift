import Testing
@testable import Telocare

struct DashboardSnapshotBuilderTests {
    @Test func buildsInputInventoryFromGraphWithPersistedState() {
        let builder = DashboardSnapshotBuilder()
        let customGraph = CausalGraphData(
            nodes: [
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "STRESS",
                        label: "Stress",
                        styleClass: "moderate",
                        confirmed: "yes",
                        tier: 2,
                        tooltip: nil
                    )
                ),
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "PPI_TX",
                        label: "PPI / Lansoprazole\nOhmure 2016 RCT",
                        styleClass: "intervention",
                        confirmed: nil,
                        tier: nil,
                        tooltip: nil
                    )
                ),
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "BED_ELEV_TX",
                        label: "Bed Elevation\n10-25cm",
                        styleClass: "intervention",
                        confirmed: nil,
                        tier: nil,
                        tooltip: nil
                    )
                ),
            ],
            edges: []
        )
        let document = UserDataDocument(
            version: 1,
            lastExport: nil,
            personalStudies: [],
            notes: [],
            experiments: [],
            interventionRatings: [
                InterventionRating(
                    interventionId: "UNTRACKED_TX",
                    effectiveness: "inconclusive",
                    notes: nil,
                    lastUpdated: "2026-02-21T09:00:00Z"
                )
            ],
            dailyCheckIns: [
                "2026-02-21": ["PPI_TX"],
                "2026-02-20": ["PPI_TX", "UNTRACKED_TX"],
            ],
            nightExposures: [],
            nightOutcomes: [],
            morningStates: [],
            habitTrials: [],
            habitClassifications: [
                HabitClassification(
                    interventionId: "BED_ELEV_TX",
                    status: .helpful,
                    nightsOn: 4,
                    nightsOff: 3,
                    microArousalDeltaPct: -10,
                    morningStateDelta: -0.6,
                    windowQuality: .cleanOneVariable,
                    updatedAt: "2026-02-21T09:00:00Z"
                )
            ],
            hiddenInterventions: ["BED_ELEV_TX"],
            unlockedAchievements: [],
            customCausalDiagram: CustomCausalDiagram(
                graphData: customGraph,
                lastModified: "2026-02-21T09:00:00Z"
            ),
            experienceFlow: .empty
        )

        let snapshot = builder.build(from: document)

        #expect(snapshot.inputs.count == 3)
        #expect(snapshot.inputs.map { $0.id } == ["PPI_TX", "BED_ELEV_TX", "UNTRACKED_TX"])
        #expect(snapshot.inputs[0].statusText == "Checked today")
        #expect(snapshot.inputs[1].classificationText == "Helpful")
        #expect(snapshot.inputs[1].isHidden)
        #expect(snapshot.inputs[2].statusText == "1/7 days")
    }

    @Test func includesAllNightOutcomesInOutcomeRecords() {
        let builder = DashboardSnapshotBuilder()
        let document = UserDataDocument(
            version: 1,
            lastExport: nil,
            personalStudies: [],
            notes: [],
            experiments: [],
            interventionRatings: [],
            dailyCheckIns: [:],
            nightExposures: [],
            nightOutcomes: [
                NightOutcome(
                    nightId: "2026-02-21",
                    microArousalCount: 10,
                    microArousalRatePerHour: 2.0,
                    confidence: 0.8,
                    totalSleepMinutes: 410,
                    source: "wearable",
                    createdAt: "2026-02-21T07:00:00Z"
                ),
                NightOutcome(
                    nightId: "2026-02-20",
                    microArousalCount: 12,
                    microArousalRatePerHour: 2.4,
                    confidence: 0.7,
                    totalSleepMinutes: 402,
                    source: "wearable",
                    createdAt: "2026-02-20T07:00:00Z"
                ),
                NightOutcome(
                    nightId: "2026-02-19",
                    microArousalCount: 13,
                    microArousalRatePerHour: 2.8,
                    confidence: 0.6,
                    totalSleepMinutes: 396,
                    source: "wearable",
                    createdAt: "2026-02-19T07:00:00Z"
                ),
            ],
            morningStates: [],
            habitTrials: [],
            habitClassifications: [],
            hiddenInterventions: [],
            unlockedAchievements: [],
            customCausalDiagram: nil,
            experienceFlow: .empty
        )

        let snapshot = builder.build(from: document)

        #expect(snapshot.outcomeRecords.count == 3)
        #expect(snapshot.outcomeRecords.first?.id == "2026-02-21")
        #expect(snapshot.outcomeRecords.last?.id == "2026-02-19")
    }

    @Test func firstPartyCatalogEnrichesInputsAndOutcomesMetadata() {
        let builder = DashboardSnapshotBuilder()
        let document = UserDataDocument(
            version: 1,
            lastExport: nil,
            personalStudies: [],
            notes: [],
            experiments: [],
            interventionRatings: [],
            dailyCheckIns: ["2026-02-21": ["PPI_TX"]],
            nightExposures: [],
            nightOutcomes: [],
            morningStates: [],
            habitTrials: [],
            habitClassifications: [],
            hiddenInterventions: [],
            unlockedAchievements: [],
            customCausalDiagram: nil,
            experienceFlow: .empty
        )
        let firstPartyContent = FirstPartyContentBundle(
            graphData: CausalGraphData(
                nodes: [],
                edges: []
            ),
            interventionsCatalog: InterventionsCatalog(
                interventions: [
                    InterventionDefinition(
                        id: "PPI_TX",
                        name: "PPI / Lansoprazole",
                        description: "Take evening dose.",
                        detailedDescription: "Take dose before bed for reflux control.",
                        evidenceLevel: "Robust",
                        evidenceSummary: "RCT-backed reduction in RMMA.",
                        citationIds: ["ohmure_2016"],
                        externalLink: "https://example.com/ppi-rct",
                        defaultOrder: 1
                    ),
                    InterventionDefinition(
                        id: "BED_ELEV_TX",
                        name: "Bed Elevation",
                        description: nil,
                        detailedDescription: nil,
                        evidenceLevel: "Moderate",
                        evidenceSummary: "Guideline-supported reflux reduction.",
                        citationIds: ["gerd_guidelines"],
                        externalLink: nil,
                        defaultOrder: 2
                    ),
                ]
            ),
            outcomesMetadata: OutcomesMetadata(
                metrics: [
                    OutcomeMetricDefinition(
                        id: "microArousalRatePerHour",
                        label: "Microarousal rate/hour",
                        unit: "events/hour",
                        direction: "lower_better",
                        description: "Lower values indicate calmer sleep continuity."
                    )
                ],
                nodes: [],
                updatedAt: "2026-02-21T21:30:00Z"
            )
        )

        let snapshot = builder.build(
            from: document,
            firstPartyContent: firstPartyContent
        )

        #expect(snapshot.inputs.map { $0.id } == ["PPI_TX", "BED_ELEV_TX"])
        #expect(snapshot.inputs.first?.evidenceLevel == "Robust")
        #expect(snapshot.inputs.first?.evidenceSummary == "RCT-backed reduction in RMMA.")
        #expect(snapshot.inputs.first?.citationIDs == ["ohmure_2016"])
        #expect(snapshot.outcomesMetadata.metrics.count == 1)
    }
}
