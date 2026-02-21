import Foundation

protocol AuthClient: Sendable {
    func currentSession() async -> AuthSession?
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String) async throws -> SignUpResult
    func signOut() async throws
}
