import Foundation
import Supabase

@MainActor
final class AppContainer {
    private let arguments: [String]
    private let environment: [String: String]
    private let accessibilityAnnouncer: AccessibilityAnnouncer

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        accessibilityAnnouncer: AccessibilityAnnouncer = .voiceOver
    ) {
        self.arguments = arguments
        self.environment = environment
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func makeRootViewModel() -> RootViewModel {
        let snapshotBuilder = DashboardSnapshotBuilder()

        if shouldUseMockServices {
            return makeMockRootViewModel(snapshotBuilder: snapshotBuilder)
        }

        do {
            let configuration = try AppConfiguration()
            let supabaseClient = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.supabasePublishableKey,
                options: SupabaseClientOptions(
                    auth: SupabaseClientOptions.AuthOptions(
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )

            return RootViewModel(
                authClient: SupabaseAuthClient(client: supabaseClient),
                userDataRepository: SupabaseUserDataRepository(client: supabaseClient),
                snapshotBuilder: snapshotBuilder,
                appleHealthDoseService: HealthKitAppleHealthDoseService(),
                accessibilityAnnouncer: accessibilityAnnouncer
            )
        } catch {
            return RootViewModel(
                authClient: MockAuthClient(),
                userDataRepository: MockUserDataRepository(document: .empty),
                snapshotBuilder: snapshotBuilder,
                appleHealthDoseService: MockAppleHealthDoseService(),
                accessibilityAnnouncer: accessibilityAnnouncer,
                bootstrapErrorMessage: error.localizedDescription
            )
        }
    }

    private var shouldUseMockServices: Bool {
        environment["TELOCARE_USE_MOCK_SERVICES"] == "1"
            || arguments.contains("--use-mock-services")
            || arguments.contains("--ui-test-authenticated")
            || arguments.contains("--ui-test-unauthenticated")
    }

    private func makeMockRootViewModel(snapshotBuilder: DashboardSnapshotBuilder) -> RootViewModel {
        let mockSession = isMockAuthenticated
            ? AuthSession(
                userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
                email: "mock-user@example.com"
            )
            : nil

        let authClient = MockAuthClient(
            initialSession: mockSession,
            signUpNeedsEmailConfirmation: shouldMockSignUpNeedConfirmation,
            signOutFails: shouldMockSignOutFail,
            signInErrorMessage: shouldMockSignInFail
                ? "Invalid login credentials"
                : nil,
            signUpErrorMessage: nil
        )

        return RootViewModel(
            authClient: authClient,
            userDataRepository: MockUserDataRepository(),
            snapshotBuilder: snapshotBuilder,
            appleHealthDoseService: MockAppleHealthDoseService(),
            accessibilityAnnouncer: accessibilityAnnouncer
        )
    }

    private var isMockAuthenticated: Bool {
        environment["TELOCARE_UI_AUTH_STATE"] == "authenticated"
            || arguments.contains("--ui-test-authenticated")
    }

    private var shouldMockSignUpNeedConfirmation: Bool {
        environment["TELOCARE_SIGNUP_NEEDS_CONFIRMATION"] == "1"
            || arguments.contains("--mock-signup-needs-confirmation")
    }

    private var shouldMockSignOutFail: Bool {
        environment["TELOCARE_SIGNOUT_FAILS"] == "1"
            || arguments.contains("--mock-signout-error")
    }

    private var shouldMockSignInFail: Bool {
        environment["TELOCARE_SIGNIN_FAILS"] == "1"
            || arguments.contains("--mock-signin-invalid-credentials")
    }
}
