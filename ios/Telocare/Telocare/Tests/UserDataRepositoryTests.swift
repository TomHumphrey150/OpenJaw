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
}
