import Foundation
import Supabase

struct SupabaseUserDataRepository: UserDataRepository {
    private let fetchRows: @Sendable (UUID) async throws -> [UserDataRow]
    private let fetchFirstParty: @Sendable (UUID) async throws -> FirstPartyContentBundle
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

        fetchFirstParty = { userID in
            async let graphData = Self.requireContentData(
                client: client,
                userID: userID,
                contentType: FirstPartyContentType.graph.rawValue,
                contentKey: FirstPartyContentKey.canonicalGraph.rawValue,
                as: CausalGraphData.self
            )
            async let interventionsCatalog = Self.requireContentData(
                client: client,
                userID: userID,
                contentType: FirstPartyContentType.inputs.rawValue,
                contentKey: FirstPartyContentKey.interventionsCatalog.rawValue,
                as: InterventionsCatalog.self
            )
            async let outcomesMetadata = Self.requireContentData(
                client: client,
                userID: userID,
                contentType: FirstPartyContentType.outcomes.rawValue,
                contentKey: FirstPartyContentKey.outcomesMetadata.rawValue,
                as: OutcomesMetadata.self
            )
            async let foundationCatalog = Self.requireContentData(
                client: client,
                userID: userID,
                contentType: FirstPartyContentType.planning.rawValue,
                contentKey: FirstPartyContentKey.foundationCatalog.rawValue,
                as: FoundationCatalog.self
            )
            async let planningPolicy = Self.requireContentData(
                client: client,
                userID: userID,
                contentType: FirstPartyContentType.planning.rawValue,
                contentKey: FirstPartyContentKey.planningPolicy.rawValue,
                as: PlanningPolicy.self
            )

            return FirstPartyContentBundle(
                graphData: try await graphData,
                interventionsCatalog: try await interventionsCatalog,
                outcomesMetadata: try await outcomesMetadata,
                foundationCatalog: try await foundationCatalog,
                planningPolicy: try await planningPolicy
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
        fetchFirstParty: @escaping @Sendable (UUID) async throws -> FirstPartyContentBundle = { _ in .empty },
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

    func fetchFirstPartyContent(userID: UUID) async throws -> FirstPartyContentBundle {
        try await fetchFirstParty(userID)
    }

    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool {
        try await backfillGraph(canonicalGraph, lastModified)
    }

    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool {
        try await upsertPatch(patch)
    }

    private static func fetchContentData<Value: Decodable>(
        client: SupabaseClient,
        userID: UUID,
        contentType: String,
        contentKey: String,
        as: Value.Type
    ) async throws -> Value? {
        if let userValue = try await fetchUserContentData(
            client: client,
            userID: userID,
            contentType: contentType,
            contentKey: contentKey,
            as: Value.self
        ) {
            return userValue
        }

        return try await fetchFirstPartyData(
            client: client,
            contentType: contentType,
            contentKey: contentKey,
            as: Value.self
        )
    }

    private static func requireContentData<Value: Decodable>(
        client: SupabaseClient,
        userID: UUID,
        contentType: String,
        contentKey: String,
        as: Value.Type
    ) async throws -> Value {
        if let value = try await fetchContentData(
            client: client,
            userID: userID,
            contentType: contentType,
            contentKey: contentKey,
            as: Value.self
        ) {
            return value
        }

        throw FirstPartyContentFetchError.missingContent(
            contentType: contentType,
            contentKey: contentKey
        )
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

    private static func fetchUserContentData<Value: Decodable>(
        client: SupabaseClient,
        userID: UUID,
        contentType: String,
        contentKey: String,
        as: Value.Type
    ) async throws -> Value? {
        let rows: [FirstPartyDataRow<Value>] = try await client
            .from("user_content")
            .select("data")
            .eq("user_id", value: userID.uuidString)
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
    case planning
}

private enum FirstPartyContentKey: String {
    case canonicalGraph = "canonical_causal_graph"
    case interventionsCatalog = "interventions_catalog"
    case outcomesMetadata = "outcomes_metadata"
    case foundationCatalog = "foundation_v1_catalog"
    case planningPolicy = "planner_policy_v1"
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

private enum FirstPartyContentFetchError: Error, LocalizedError {
    case missingContent(contentType: String, contentKey: String)

    var errorDescription: String? {
        switch self {
        case .missingContent(let contentType, let contentKey):
            return "Missing Supabase content row: \(contentType)/\(contentKey)."
        }
    }
}
