import Foundation

struct MockUserDataRepository: UserDataRepository {
    let document: UserDataDocument

    init(document: UserDataDocument = .mockForUI) {
        self.document = document
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        _ = userID
        return document
    }

    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool {
        _ = canonicalGraph
        _ = lastModified
        return false
    }

    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool {
        _ = patch
        return false
    }
}
