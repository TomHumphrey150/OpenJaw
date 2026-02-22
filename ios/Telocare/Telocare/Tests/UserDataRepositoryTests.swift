import Foundation
import Testing
@testable import Telocare

struct UserDataRepositoryTests {
    @Test func returnsEmptyDocumentWhenNoSupabaseRowExists() async throws {
        let repository = SupabaseUserDataRepository { _ in
            []
        }

        let result = try await repository.fetch(userID: UUID())
        #expect(result == .empty)
    }

    @Test func returnsDecodedDocumentWhenRowExists() async throws {
        let repository = SupabaseUserDataRepository { _ in
            [UserDataRow(data: .mockForUI)]
        }

        let result = try await repository.fetch(userID: UUID())
        #expect(result.customCausalDiagram?.graphData.nodes.isEmpty == false)
        #expect(result.dailyCheckIns.isEmpty == false)
    }

    @Test func backfillReturnsClosureResult() async throws {
        let repository = SupabaseUserDataRepository(
            fetchRows: { _ in [] },
            backfillGraph: { _, _ in true }
        )

        let didWrite = try await repository.backfillDefaultGraphIfMissing(
            canonicalGraph: .defaultGraph,
            lastModified: "2026-02-21T18:30:00Z"
        )

        #expect(didWrite == true)
    }

    @Test func backfillPropagatesFailures() async {
        let repository = SupabaseUserDataRepository(
            fetchRows: { _ in [] },
            backfillGraph: { _, _ in throw RepositoryFailure.backfillFailed }
        )

        await #expect(throws: RepositoryFailure.self) {
            _ = try await repository.backfillDefaultGraphIfMissing(
                canonicalGraph: .defaultGraph,
                lastModified: "2026-02-21T18:30:00Z"
            )
        }
    }

    @Test func upsertPatchReturnsClosureResult() async throws {
        let repository = SupabaseUserDataRepository(
            fetchRows: { _ in [] },
            backfillGraph: { _, _ in false },
            upsertPatch: { _ in true }
        )

        let result = try await repository.upsertUserDataPatch(
            .experienceFlow(
                ExperienceFlow(
                    hasCompletedInitialGuidedFlow: true,
                    lastGuidedEntryDate: "2026-02-21",
                    lastGuidedCompletedDate: "2026-02-21",
                    lastGuidedStatus: .completed
                )
            )
        )

        #expect(result == true)
    }

    @Test func upsertPatchPropagatesFailures() async {
        let repository = SupabaseUserDataRepository(
            fetchRows: { _ in [] },
            backfillGraph: { _, _ in false },
            upsertPatch: { _ in throw RepositoryFailure.patchFailed }
        )

        await #expect(throws: RepositoryFailure.self) {
            _ = try await repository.upsertUserDataPatch(
                .experienceFlow(
                    ExperienceFlow(
                        hasCompletedInitialGuidedFlow: false,
                        lastGuidedEntryDate: "2026-02-21",
                        lastGuidedCompletedDate: nil,
                        lastGuidedStatus: .inProgress
                    )
                )
            )
        }
    }

    @Test func fetchFirstPartyContentReturnsClosureResult() async throws {
        let expected = FirstPartyContentBundle(
            graphData: .defaultGraph,
            interventionsCatalog: InterventionsCatalog(
                interventions: [
                    InterventionDefinition(
                        id: "PPI_TX",
                        name: "PPI / Lansoprazole",
                        description: nil,
                        detailedDescription: nil,
                        evidenceLevel: "Robust",
                        evidenceSummary: "RCT support",
                        citationIds: ["ohmure_2016"],
                        externalLink: nil,
                        defaultOrder: 1
                    )
                ]
            ),
            outcomesMetadata: OutcomesMetadata(
                metrics: [
                    OutcomeMetricDefinition(
                        id: "microArousalRatePerHour",
                        label: "Microarousal rate per hour",
                        unit: "events/hour",
                        direction: "lower_better",
                        description: "Lower values indicate calmer sleep continuity."
                    )
                ],
                nodes: [],
                updatedAt: "2026-02-21T21:30:00Z"
            )
        )

        let repository = SupabaseUserDataRepository(
            fetchRows: { _ in [] },
            fetchFirstParty: { expected }
        )

        let result = try await repository.fetchFirstPartyContent()
        #expect(result == expected)
    }

    @Test func fetchFirstPartyContentPropagatesFailures() async {
        let repository = SupabaseUserDataRepository(
            fetchRows: { _ in [] },
            fetchFirstParty: { throw RepositoryFailure.firstPartyFailed }
        )

        await #expect(throws: RepositoryFailure.self) {
            _ = try await repository.fetchFirstPartyContent()
        }
    }

    @Test func userDataPatchEncodingUsesExpectedKeys() throws {
        let patch = UserDataPatch.experienceFlow(
            ExperienceFlow(
                hasCompletedInitialGuidedFlow: true,
                lastGuidedEntryDate: "2026-02-21",
                lastGuidedCompletedDate: "2026-02-21",
                lastGuidedStatus: .completed
            )
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.experienceFlow?.lastGuidedStatus == .completed)
        #expect(decoded.experienceFlow?.hasCompletedInitialGuidedFlow == true)
        #expect(decoded.dailyCheckIns == nil)
        #expect(decoded.interventionCompletionEvents == nil)
        #expect(decoded.nightOutcomes == nil)
        #expect(decoded.morningStates == nil)
        #expect(decoded.activeInterventions == nil)
        #expect(decoded.hiddenInterventions == nil)
        #expect(decoded.customCausalDiagram == nil)
        #expect(decoded.wakeDaySleepAttributionMigrated == nil)
    }

    @Test func userDataPatchCanEncodeMorningStates() throws {
        let patch = UserDataPatch.morningStates(
            [
                MorningState(
                    nightId: "2026-02-21",
                    globalSensation: 6,
                    neckTightness: 4,
                    jawSoreness: 3,
                    earFullness: 2,
                    healthAnxiety: 5,
                    createdAt: "2026-02-21T07:40:00Z"
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.experienceFlow == nil)
        #expect(decoded.dailyCheckIns == nil)
        #expect(decoded.interventionCompletionEvents == nil)
        #expect(decoded.nightOutcomes == nil)
        #expect(decoded.morningStates?.count == 1)
        #expect(decoded.morningStates?.first?.nightId == "2026-02-21")
        #expect(decoded.morningStates?.first?.globalSensation == 6)
        #expect(decoded.activeInterventions == nil)
        #expect(decoded.hiddenInterventions == nil)
        #expect(decoded.customCausalDiagram == nil)
    }

    @Test func userDataPatchCanEncodeNightOutcomes() throws {
        let patch = UserDataPatch.nightOutcomes(
            [
                NightOutcome(
                    nightId: "2026-02-22",
                    microArousalCount: 14,
                    microArousalRatePerHour: 2.8,
                    confidence: 0.71,
                    totalSleepMinutes: 360,
                    source: "muse_athena_heuristic_v1",
                    createdAt: "2026-02-22T07:40:00Z"
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.nightOutcomes?.count == 1)
        #expect(decoded.nightOutcomes?.first?.nightId == "2026-02-22")
        #expect(decoded.nightOutcomes?.first?.microArousalRatePerHour == 2.8)
        #expect(decoded.morningStates == nil)
        #expect(decoded.wakeDaySleepAttributionMigrated == nil)
    }

    @Test func userDataPatchCanEncodeSleepAttributionMigration() throws {
        let patch = UserDataPatch.sleepAttributionMigration(
            dailyDoseProgress: [
                "2026-02-22": ["sleep_hours": 7.5]
            ],
            nightOutcomes: [
                NightOutcome(
                    nightId: "2026-02-22",
                    microArousalCount: 10,
                    microArousalRatePerHour: 1.8,
                    confidence: 0.77,
                    totalSleepMinutes: 420,
                    source: "wearable",
                    createdAt: "2026-02-22T07:45:00Z"
                )
            ],
            morningStates: [
                MorningState(
                    nightId: "2026-02-22",
                    globalSensation: 4,
                    neckTightness: 3,
                    jawSoreness: 2,
                    earFullness: 2,
                    healthAnxiety: 3,
                    stressLevel: 4,
                    createdAt: "2026-02-22T08:10:00Z"
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.dailyDoseProgress?["2026-02-22"]?["sleep_hours"] == 7.5)
        #expect(decoded.nightOutcomes?.first?.nightId == "2026-02-22")
        #expect(decoded.morningStates?.first?.nightId == "2026-02-22")
        #expect(decoded.wakeDaySleepAttributionMigrated == true)
    }

    @Test func userDataPatchCanEncodeDailyCheckIns() throws {
        let patch = UserDataPatch.dailyCheckIns(
            [
                "2026-02-21": ["PPI_TX", "REFLUX_DIET_TX"]
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.experienceFlow == nil)
        #expect(decoded.dailyCheckIns?["2026-02-21"] == ["PPI_TX", "REFLUX_DIET_TX"])
        #expect(decoded.morningStates == nil)
        #expect(decoded.activeInterventions == nil)
        #expect(decoded.hiddenInterventions == nil)
    }

    @Test func userDataPatchCanEncodeDailyDoseProgress() throws {
        let patch = UserDataPatch.dailyDoseProgress(
            [
                "2026-02-21": ["water_intake": 1200]
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.dailyDoseProgress?["2026-02-21"]?["water_intake"] == 1200)
        #expect(decoded.interventionDoseSettings == nil)
    }

    @Test func userDataPatchCanEncodeInterventionCompletionEvents() throws {
        let patch = UserDataPatch.interventionCompletionEvents(
            [
                InterventionCompletionEvent(
                    interventionId: "PPI_TX",
                    occurredAt: "2026-02-21T08:00:00Z",
                    source: .binaryCheck
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.interventionCompletionEvents?.count == 1)
        #expect(decoded.interventionCompletionEvents?.first?.source == .binaryCheck)
        #expect(decoded.dailyCheckIns == nil)
        #expect(decoded.dailyDoseProgress == nil)
    }

    @Test func userDataPatchCanEncodeDailyCheckInsAndCompletionEventsAtomically() throws {
        let patch = UserDataPatch.dailyCheckInsAndCompletionEvents(
            ["2026-02-21": ["PPI_TX"]],
            [
                InterventionCompletionEvent(
                    interventionId: "PPI_TX",
                    occurredAt: "2026-02-21T08:00:00Z",
                    source: .binaryCheck
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.dailyCheckIns?["2026-02-21"] == ["PPI_TX"])
        #expect(decoded.interventionCompletionEvents?.count == 1)
        #expect(decoded.dailyDoseProgress == nil)
    }

    @Test func userDataPatchCanEncodeDailyDoseProgressAndCompletionEventsAtomically() throws {
        let patch = UserDataPatch.dailyDoseProgressAndCompletionEvents(
            ["2026-02-21": ["water_intake": 1200]],
            [
                InterventionCompletionEvent(
                    interventionId: "water_intake",
                    occurredAt: "2026-02-21T08:00:00Z",
                    source: .doseIncrement
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.dailyDoseProgress?["2026-02-21"]?["water_intake"] == 1200)
        #expect(decoded.interventionCompletionEvents?.first?.source == .doseIncrement)
        #expect(decoded.dailyCheckIns == nil)
    }

    @Test func userDataPatchCanEncodeInterventionDoseSettings() throws {
        let patch = UserDataPatch.interventionDoseSettings(
            [
                "water_intake": DoseSettings(dailyGoal: 3000, increment: 100)
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.dailyDoseProgress == nil)
        #expect(decoded.interventionDoseSettings?["water_intake"]?.dailyGoal == 3000)
        #expect(decoded.interventionDoseSettings?["water_intake"]?.increment == 100)
    }

    @Test func userDataPatchCanEncodeAppleHealthConnections() throws {
        let patch = UserDataPatch.appleHealthConnections(
            [
                "water_intake": AppleHealthConnection(
                    isConnected: true,
                    connectedAt: "2026-02-22T10:00:00Z",
                    lastSyncAt: "2026-02-22T10:05:00Z",
                    lastSyncStatus: .synced,
                    lastErrorCode: nil
                )
            ]
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.appleHealthConnections?["water_intake"]?.isConnected == true)
        #expect(decoded.appleHealthConnections?["water_intake"]?.lastSyncStatus == .synced)
    }

    @Test func userDataPatchCanEncodeActiveInterventions() throws {
        let patch = UserDataPatch.activeInterventions(["PPI_TX", "BED_ELEV_TX"])

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.experienceFlow == nil)
        #expect(decoded.dailyCheckIns == nil)
        #expect(decoded.morningStates == nil)
        #expect(decoded.activeInterventions == ["PPI_TX", "BED_ELEV_TX"])
        #expect(decoded.hiddenInterventions == nil)
    }

    @Test func userDataPatchCanEncodeHiddenInterventions() throws {
        let patch = UserDataPatch.hiddenInterventions(["PPI_TX", "BED_ELEV_TX"])

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.experienceFlow == nil)
        #expect(decoded.dailyCheckIns == nil)
        #expect(decoded.morningStates == nil)
        #expect(decoded.hiddenInterventions == ["PPI_TX", "BED_ELEV_TX"])
        #expect(decoded.customCausalDiagram == nil)
    }

    @Test func userDataPatchCanEncodeCustomCausalDiagram() throws {
        let graph = CausalGraphData(
            nodes: [
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "RMMA",
                        label: "RMMA",
                        styleClass: "robust",
                        confirmed: "yes",
                        tier: 7,
                        tooltip: nil,
                        isDeactivated: true
                    )
                )
            ],
            edges: [
                GraphEdgeElement(
                    data: GraphEdgeData(
                        source: "RMMA",
                        target: "NECK_TIGHTNESS",
                        label: nil,
                        edgeType: "forward",
                        edgeColor: "#1e3a5f",
                        tooltip: nil,
                        isDeactivated: true
                    )
                )
            ]
        )
        let patch = UserDataPatch.customCausalDiagram(
            CustomCausalDiagram(
                graphData: graph,
                lastModified: "2026-02-22T10:00:00Z"
            )
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(DecodedPatch.self, from: data)

        #expect(decoded.customCausalDiagram?.graphData.nodes.first?.data.id == "RMMA")
        #expect(decoded.customCausalDiagram?.graphData.nodes.first?.data.isDeactivated == true)
        #expect(decoded.customCausalDiagram?.graphData.edges.first?.data.isDeactivated == true)
        #expect(decoded.dailyCheckIns == nil)
        #expect(decoded.activeInterventions == nil)
    }
}

private enum RepositoryFailure: Error {
    case backfillFailed
    case patchFailed
    case firstPartyFailed
}

private struct DecodedPatch: Decodable {
    let experienceFlow: ExperienceFlow?
    let dailyCheckIns: [String: [String]]?
    let dailyDoseProgress: [String: [String: Double]]?
    let interventionCompletionEvents: [InterventionCompletionEvent]?
    let interventionDoseSettings: [String: DoseSettings]?
    let appleHealthConnections: [String: AppleHealthConnection]?
    let nightOutcomes: [NightOutcome]?
    let morningStates: [MorningState]?
    let activeInterventions: [String]?
    let hiddenInterventions: [String]?
    let customCausalDiagram: CustomCausalDiagram?
    let wakeDaySleepAttributionMigrated: Bool?
}
