import Testing
@testable import Telocare

struct AuthUtilitiesTests {
    @Test func normalizesEmailBeforeAuthCalls() {
        let normalized = AuthEmailNormalizer.normalize("  USER@Example.COM ")
        #expect(normalized == "user@example.com")
    }

    @Test func mapsInvalidCredentialsToActionableSignInMessage() {
        let message = AuthErrorMessageMapper.message(
            for: MockAuthError(message: "Invalid login credentials"),
            operation: .signIn
        )

        #expect(message.contains("Invalid email/password"))
    }

    @Test func mapsSignupDisabledMessage() {
        let message = AuthErrorMessageMapper.message(
            for: MockAuthError(message: "Signup is disabled"),
            operation: .signUp
        )

        #expect(message.contains("Account creation is disabled"))
    }
}
