import Foundation
import Supabase

struct SupabaseUserDataRepository: UserDataRepository {
    private let fetchRows: @Sendable (UUID) async throws -> [UserDataRow]
    private let fetchFirstParty: @Sendable () async throws -> FirstPartyContentBundle
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

        fetchFirstParty = {
            async let graphData = Self.fetchFirstPartyData(
                client: client,
                contentType: FirstPartyContentType.graph.rawValue,
                contentKey: FirstPartyContentKey.canonicalGraph.rawValue,
                as: CausalGraphData.self
            )
            async let interventionsCatalog = Self.fetchFirstPartyData(
                client: client,
                contentType: FirstPartyContentType.inputs.rawValue,
                contentKey: FirstPartyContentKey.interventionsCatalog.rawValue,
                as: InterventionsCatalog.self
            )
            async let outcomesMetadata = Self.fetchFirstPartyData(
                client: client,
                contentType: FirstPartyContentType.outcomes.rawValue,
                contentKey: FirstPartyContentKey.outcomesMetadata.rawValue,
                as: OutcomesMetadata.self
            )

            return FirstPartyContentBundle(
                graphData: try await graphData,
                interventionsCatalog: try await interventionsCatalog ?? .empty,
                outcomesMetadata: try await outcomesMetadata ?? .empty
            )
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
        fetchFirstParty: @escaping @Sendable () async throws -> FirstPartyContentBundle = { .empty },
        backfillGraph: @escaping @Sendable (CausalGraphData, String) async throws -> Bool = { _, _ in false },
        upsertPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in false }
    ) {
        self.fetchRows = fetchRows
        self.fetchFirstParty = fetchFirstParty
        self.backfillGraph = backfillGraph
        self.upsertPatch = upsertPatch
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        let rows = try await fetchRows(userID)
        return rows.first?.data ?? .empty
    }

    func fetchFirstPartyContent() async throws -> FirstPartyContentBundle {
        try await fetchFirstParty()
    }

    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool {
        try await backfillGraph(canonicalGraph, lastModified)
    }

    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool {
        try await upsertPatch(patch)
    }

    private static func fetchFirstPartyData<Value: Decodable>(
        client: SupabaseClient,
        contentType: String,
        contentKey: String,
        as: Value.Type
    ) async throws -> Value? {
        let rows: [FirstPartyDataRow<Value>] = try await client
            .from("first_party_content")
            .select("data")
            .eq("content_type", value: contentType)
            .eq("content_key", value: contentKey)
            .limit(1)
            .execute()
            .value

        return rows.first?.data
    }
}

struct UserDataRow: Decodable, Equatable {
    let data: UserDataDocument
}

private struct FirstPartyDataRow<Value: Decodable>: Decodable {
    let data: Value
}

private enum FirstPartyContentType: String {
    case graph
    case inputs
    case outcomes
}

private enum FirstPartyContentKey: String {
    case canonicalGraph = "canonical_causal_graph"
    case interventionsCatalog = "interventions_catalog"
    case outcomesMetadata = "outcomes_metadata"
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
