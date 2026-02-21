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
        #expect(decoded.morningStates == nil)
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
        #expect(decoded.morningStates?.count == 1)
        #expect(decoded.morningStates?.first?.nightId == "2026-02-21")
        #expect(decoded.morningStates?.first?.globalSensation == 6)
    }
}

private enum RepositoryFailure: Error {
    case backfillFailed
    case patchFailed
    case firstPartyFailed
}

private struct DecodedPatch: Decodable {
    let experienceFlow: ExperienceFlow?
    let morningStates: [MorningState]?
}
