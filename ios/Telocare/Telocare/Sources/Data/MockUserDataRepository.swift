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
}
