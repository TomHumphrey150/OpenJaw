import Testing
@testable import Telocare

@MainActor
struct RootViewModelTests {
    @Test func bootstrapWithoutSessionShowsAuthState() async {
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: MockUserDataRepository(),
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }
        #expect(viewModel.state == .auth)
    }

    @Test func signInTransitionsFromAuthToReady() async {
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: MockUserDataRepository(),
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "user@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignIn()

        await waitUntil { viewModel.state == .ready }
        #expect(viewModel.dashboardViewModel != nil)
    }

    @Test func signUpNeedsConfirmationKeepsAuthStateAndShowsStatus() async {
        let viewModel = RootViewModel(
            authClient: MockAuthClient(signUpNeedsEmailConfirmation: true),
            userDataRepository: MockUserDataRepository(),
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "new@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignUp()

        await waitUntil { viewModel.authStatusMessage != nil }
        #expect(viewModel.state == .auth)
        #expect(viewModel.authStatusMessage?.contains("Account created.") == true)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<120 {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
