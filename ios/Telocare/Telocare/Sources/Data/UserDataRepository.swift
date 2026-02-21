import Foundation

protocol UserDataRepository: Sendable {
    func fetch(userID: UUID) async throws -> UserDataDocument
    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool
    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool
}
