import Foundation

struct MockUserDataRepository: UserDataRepository {
    let document: UserDataDocument
    let firstPartyContent: FirstPartyContentBundle

    init(
        document: UserDataDocument = .mockForUI,
        firstPartyContent: FirstPartyContentBundle = .empty
    ) {
        self.document = document
        self.firstPartyContent = firstPartyContent
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        _ = userID
        return document
    }

    func fetchFirstPartyContent() async throws -> FirstPartyContentBundle {
        firstPartyContent
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
}
