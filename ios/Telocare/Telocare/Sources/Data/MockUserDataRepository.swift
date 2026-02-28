import Foundation

struct MockUserDataRepository: UserDataRepository {
    let document: UserDataDocument
    let firstPartyContent: FirstPartyContentBundle

    init(
        document: UserDataDocument = .mockForUI,
        firstPartyContent: FirstPartyContentBundle = Self.defaultFirstPartyContent
    ) {
        self.document = document
        self.firstPartyContent = firstPartyContent
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        _ = userID
        return document
    }

    func fetchFirstPartyContent(userID: UUID) async throws -> FirstPartyContentBundle {
        _ = userID
        return firstPartyContent
    }

    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool {
        _ = canonicalGraph
        _ = lastModified
        return false
    }

    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool {
        _ = patch
        return true
    }

    private static let defaultFirstPartyContent = FirstPartyContentBundle(
        graphData: .defaultGraph,
        interventionsCatalog: .empty,
        outcomesMetadata: .empty,
        foundationCatalog: FoundationCatalog(
            schemaVersion: "mock.foundation.v1",
            sourceReportPath: "mock",
            generatedAt: "mock",
            pillars: [],
            interventionMappings: []
        ),
        planningPolicy: .default
    )
}
