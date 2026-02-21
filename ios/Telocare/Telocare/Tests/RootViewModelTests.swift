import Foundation
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

    @Test func missingCustomGraphTriggersBackfill() async {
        let repository = TrackingUserDataRepository(document: .empty)
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: repository,
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "user@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignIn()

        await waitUntil { viewModel.state == .ready }
        await waitUntil { await repository.backfillCallCount() == 1 }
    }

    @Test func existingCustomGraphSkipsBackfill() async {
        let repository = TrackingUserDataRepository(document: .mockForUI)
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: repository,
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "user@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignIn()

        await waitUntil { viewModel.state == .ready }
        #expect(await repository.backfillCallCount() == 0)
    }

    @Test func backfillFailureIsNonFatal() async {
        let repository = TrackingUserDataRepository(
            document: .empty,
            backfillShouldThrow: true
        )
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: repository,
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "user@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignIn()

        await waitUntil { viewModel.state == .ready }
        await waitUntil { await repository.backfillCallCount() == 1 }
        #expect(viewModel.dashboardViewModel != nil)
    }

    @Test func guidedEntryPersistsExperienceFlowPatch() async {
        let repository = TrackingUserDataRepository(document: .empty)
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: repository,
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "user@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignIn()

        await waitUntil { viewModel.state == .ready }
        await waitUntil { await repository.patchCallCount() == 1 }
    }

    @Test func patchPersistenceFailureIsNonFatal() async {
        let repository = TrackingUserDataRepository(
            document: .empty,
            patchShouldThrow: true
        )
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: repository,
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in }
        )

        await waitUntil { viewModel.state == .auth }

        viewModel.authEmail = "user@example.com"
        viewModel.authPassword = "Password123!"
        viewModel.submitSignIn()

        await waitUntil { viewModel.state == .ready }
        await waitUntil { await repository.patchCallCount() == 1 }
        #expect(viewModel.dashboardViewModel != nil)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

actor TrackingUserDataRepository: UserDataRepository {
    private let document: UserDataDocument
    private let backfillShouldThrow: Bool
    private let patchShouldThrow: Bool
    private var calls: Int = 0
    private var patchCalls: Int = 0

    init(
        document: UserDataDocument,
        backfillShouldThrow: Bool = false,
        patchShouldThrow: Bool = false
    ) {
        self.document = document
        self.backfillShouldThrow = backfillShouldThrow
        self.patchShouldThrow = patchShouldThrow
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        _ = userID
        return document
    }

    func backfillDefaultGraphIfMissing(canonicalGraph: CausalGraphData, lastModified: String) async throws -> Bool {
        _ = canonicalGraph
        _ = lastModified
        calls += 1

        if backfillShouldThrow {
            throw TrackingRepositoryError.backfillFailed
        }

        return true
    }

    func backfillCallCount() -> Int {
        calls
    }

    func upsertUserDataPatch(_ patch: UserDataPatch) async throws -> Bool {
        _ = patch
        patchCalls += 1

        if patchShouldThrow {
            throw TrackingRepositoryError.patchFailed
        }

        return true
    }

    func patchCallCount() -> Int {
        patchCalls
    }
}

private enum TrackingRepositoryError: Error {
    case backfillFailed
    case patchFailed
}
