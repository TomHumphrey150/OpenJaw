import Foundation

protocol UserDataRepository: Sendable {
    func fetch(userID: UUID) async throws -> UserDataDocument
}
