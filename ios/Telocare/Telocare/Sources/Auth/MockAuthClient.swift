import Foundation

actor MockAuthClient: AuthClient {
    private var session: AuthSession?
    private let signUpNeedsEmailConfirmation: Bool
    private let signOutFails: Bool
    private let signInErrorMessage: String?
    private let signUpErrorMessage: String?
    private let userID: UUID

    init(
        initialSession: AuthSession? = nil,
        signUpNeedsEmailConfirmation: Bool = false,
        signOutFails: Bool = false,
        signInErrorMessage: String? = nil,
        signUpErrorMessage: String? = nil
    ) {
        session = initialSession
        self.signUpNeedsEmailConfirmation = signUpNeedsEmailConfirmation
        self.signOutFails = signOutFails
        self.signInErrorMessage = signInErrorMessage
        self.signUpErrorMessage = signUpErrorMessage
        userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    }

    func currentSession() async -> AuthSession? {
        session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        if let signInErrorMessage {
            throw MockAuthError(message: signInErrorMessage)
        }

        let normalizedEmail = AuthEmailNormalizer.normalize(email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw AuthInputError.missingCredentials
        }

        let nextSession = AuthSession(userID: userID, email: normalizedEmail)
        session = nextSession
        return nextSession
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        if let signUpErrorMessage {
            throw MockAuthError(message: signUpErrorMessage)
        }

        let normalizedEmail = AuthEmailNormalizer.normalize(email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw AuthInputError.missingCredentials
        }

        if signUpNeedsEmailConfirmation {
            return .needsEmailConfirmation
        }

        let nextSession = AuthSession(userID: userID, email: normalizedEmail)
        session = nextSession
        return .authenticated(nextSession)
    }

    func signOut() async throws {
        if signOutFails {
            throw MockAuthError(message: "mock sign-out failed")
        }

        session = nil
    }
}

struct MockAuthError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}
