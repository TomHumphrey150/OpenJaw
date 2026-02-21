import Foundation

struct AuthSession: Equatable, Sendable {
    let userID: UUID
    let email: String?
}

enum SignUpResult: Equatable, Sendable {
    case authenticated(AuthSession)
    case needsEmailConfirmation
}

enum AuthOperation {
    case signIn
    case signUp
}

enum AuthInputError: Error {
    case missingCredentials
}
