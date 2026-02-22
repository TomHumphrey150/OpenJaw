import Foundation
import Supabase

struct SupabaseAuthClient: AuthClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentSession() async -> AuthSession? {
        let session: Session

        do {
            session = try await client.auth.session
        } catch {
            return nil
        }

        return AuthSession(
            userID: session.user.id,
            email: session.user.email
        )
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let normalizedEmail = AuthEmailNormalizer.normalize(email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw AuthInputError.missingCredentials
        }

        let session = try await client.auth.signIn(email: normalizedEmail, password: password)
        return AuthSession(userID: session.user.id, email: session.user.email)
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        let normalizedEmail = AuthEmailNormalizer.normalize(email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw AuthInputError.missingCredentials
        }

        let response = try await client.auth.signUp(email: normalizedEmail, password: password)

        switch response {
        case .session(let session):
            return .authenticated(AuthSession(userID: session.user.id, email: session.user.email))
        case .user:
            return .needsEmailConfirmation
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
