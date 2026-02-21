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

        #expect(decoded.experienceFlow.lastGuidedStatus == .completed)
        #expect(decoded.experienceFlow.hasCompletedInitialGuidedFlow == true)
    }
}

private enum RepositoryFailure: Error {
    case backfillFailed
    case patchFailed
}

private struct DecodedPatch: Decodable {
    let experienceFlow: ExperienceFlow
}
