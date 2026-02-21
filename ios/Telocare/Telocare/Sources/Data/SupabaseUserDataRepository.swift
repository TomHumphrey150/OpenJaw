import Foundation
import Supabase

struct SupabaseUserDataRepository: UserDataRepository {
    private let fetchRows: @Sendable (UUID) async throws -> [UserDataRow]
    private let backfillGraph: @Sendable (CausalGraphData, String) async throws -> Bool
    private let upsertPatch: @Sendable (UserDataPatch) async throws -> Bool

    init(client: SupabaseClient) {
        fetchRows = { userID in
            try await client
                .from("user_data")
                .select("data")
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
        }

        backfillGraph = { canonicalGraph, lastModified in
            let request = BackfillDefaultGraphRequest(
                graphData: canonicalGraph,
                lastModified: lastModified
            )

            let didWrite: Bool = try await client
                .rpc("backfill_default_graph_if_missing", params: request)
                .execute()
                .value
            return didWrite
        }

        upsertPatch = { patch in
            let request = UpsertUserDataPatchRequest(patch: patch)
            let didWrite: Bool = try await client
                .rpc("upsert_user_data_patch", params: request)
                .execute()
                .value
            return didWrite
        }
    }

    init(
        fetchRows: @escaping @Sendable (UUID) async throws -> [UserDataRow],
        backfillGraph: @escaping @Sendable (CausalGraphData, String) async throws -> Bool = { _, _ in false },
        upsertPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in false }
    ) {
        self.fetchRows = fetchRows
        self.backfillGraph = backfillGraph
        self.upsertPatch = upsertPatch
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        let rows = try await fetchRows(userID)
        return rows.first?.data ?? .empty
    }

    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool {
        try await backfillGraph(canonicalGraph, lastModified)
    }

    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool {
        try await upsertPatch(patch)
    }
}

struct UserDataRow: Decodable, Equatable {
    let data: UserDataDocument
}

private struct BackfillDefaultGraphRequest: Encodable {
    let graphData: CausalGraphData
    let lastModified: String

    private enum CodingKeys: String, CodingKey {
        case graphData = "graph_data"
        case lastModified = "last_modified"
    }
}

private struct UpsertUserDataPatchRequest: Encodable {
    let patch: UserDataPatch
}
