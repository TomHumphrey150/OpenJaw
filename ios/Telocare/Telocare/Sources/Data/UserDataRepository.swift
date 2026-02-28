import Foundation

protocol UserDataRepository: Sendable {
    func fetch(userID: UUID) async throws -> UserDataDocument
    func fetchFirstPartyContent(userID: UUID) async throws -> FirstPartyContentBundle
    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool
    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool
}
