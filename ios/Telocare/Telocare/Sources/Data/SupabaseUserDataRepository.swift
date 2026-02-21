import Foundation
import Supabase

struct SupabaseUserDataRepository: UserDataRepository {
    private let fetchRows: @Sendable (UUID) async throws -> [UserDataRow]

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
    }

    init(fetchRows: @escaping @Sendable (UUID) async throws -> [UserDataRow]) {
        self.fetchRows = fetchRows
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        let rows = try await fetchRows(userID)
        return rows.first?.data ?? .empty
    }
}

struct UserDataRow: Decodable, Equatable {
    let data: UserDataDocument
}
