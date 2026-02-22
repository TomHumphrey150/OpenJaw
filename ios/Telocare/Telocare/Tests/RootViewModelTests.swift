import Foundation
import Testing
@testable import Telocare

@MainActor
struct RootViewModelTests {
    @Test func setSkinUpdatesSelectionAndPersistsPreference() async {
        var persistedSkins: [TelocareSkinID] = []
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: MockUserDataRepository(),
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in },
            initialSkinID: .warmCoral,
            persistSkinPreference: { skinID in
                persistedSkins.append(skinID)
            }
        )

        await waitUntil { viewModel.state == .auth }
        viewModel.setSkin(.garden)

        #expect(viewModel.selectedSkinID == .garden)
        #expect(persistedSkins == [.garden])
    }

    @Test func setSkinDoesNotPersistWhenSelectionIsUnchanged() async {
        var persistCallCount = 0
        let viewModel = RootViewModel(
            authClient: MockAuthClient(),
            userDataRepository: MockUserDataRepository(),
            snapshotBuilder: DashboardSnapshotBuilder(),
            accessibilityAnnouncer: AccessibilityAnnouncer { _ in },
            initialSkinID: .warmCoral,
            persistSkinPreference: { _ in
                persistCallCount += 1
            }
        )

        await waitUntil { viewModel.state == .auth }
        viewModel.setSkin(.warmCoral)

        #expect(viewModel.selectedSkinID == .warmCoral)
        #expect(persistCallCount == 0)
    }

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
        #expect(viewModel.dashboardViewModel?.mode == .explore)
        #expect(viewModel.dashboardViewModel?.selectedExploreTab == .inputs)
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

    @Test func existingCustomGraphWithoutDeactivationFlagsPersistsDormantMigrationPatch() async {
        let graphData = CausalGraphData(
            nodes: [
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "OSA",
                        label: "Sleep Apnea / UARS",
                        styleClass: "mechanism",
                        confirmed: "no",
                        tier: 1,
                        tooltip: nil
                    )
                ),
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "RMMA",
                        label: "RMMA",
                        styleClass: "robust",
                        confirmed: "yes",
                        tier: 7,
                        tooltip: nil
                    )
                )
            ],
            edges: [
                GraphEdgeElement(
                    data: GraphEdgeData(
                        source: "OSA",
                        target: "RMMA",
                        label: nil,
                        edgeType: "forward",
                        edgeColor: "#374151",
                        tooltip: nil
                    )
                )
            ]
        )
        let document = UserDataDocument.empty.withCustomCausalDiagram(
            CustomCausalDiagram(
                graphData: graphData,
                lastModified: "2026-02-21T00:00:00Z"
            )
        )
        let repository = TrackingUserDataRepository(document: document)
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

        let patch = await repository.lastPatch()
        #expect(patch?.customCausalDiagram?.graphData.nodes.first?.data.isDeactivated == true)
        #expect(patch?.customCausalDiagram?.graphData.edges.first?.data.isDeactivated == true)
    }

    @Test func existingCustomGraphWithExplicitDeactivationSkipsDormantMigrationPatch() async {
        let graphData = CausalGraphData(
            nodes: [
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "OSA",
                        label: "Sleep Apnea / UARS",
                        styleClass: "mechanism",
                        confirmed: "no",
                        tier: 1,
                        tooltip: nil,
                        isDeactivated: true
                    )
                ),
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "RMMA",
                        label: "RMMA",
                        styleClass: "robust",
                        confirmed: "yes",
                        tier: 7,
                        tooltip: nil
                    )
                )
            ],
            edges: [
                GraphEdgeElement(
                    data: GraphEdgeData(
                        source: "OSA",
                        target: "RMMA",
                        label: nil,
                        edgeType: "forward",
                        edgeColor: "#374151",
                        tooltip: nil
                    )
                )
            ]
        )
        let document = UserDataDocument.empty.withCustomCausalDiagram(
            CustomCausalDiagram(
                graphData: graphData,
                lastModified: "2026-02-21T00:00:00Z"
            )
        )
        let repository = TrackingUserDataRepository(document: document)
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
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(await repository.patchCallCount() == 0)
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

    @Test func hydrationDoesNotPersistUserPatchUntilUserAction() async {
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
        #expect(await repository.patchCallCount() == 0)
    }

    @Test func togglingInputCheckPersistsPatch() async {
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
        viewModel.dashboardViewModel?.toggleInputCheckedToday("PPI_TX")

        await waitUntil { await repository.patchCallCount() == 1 }
        let includesIntervention = await repository.lastPatch()?.dailyCheckIns?.values.contains { ids in
            ids.contains("PPI_TX")
        }
        #expect(includesIntervention == true)
    }

    @Test func togglingInputActivationPersistsPatch() async {
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
        viewModel.dashboardViewModel?.toggleInputActive("PPI_TX")

        await waitUntil { await repository.patchCallCount() == 1 }
        #expect(await repository.lastPatch()?.activeInterventions?.contains("PPI_TX") == true)
    }

    @Test func selectingMorningOutcomePersistsPatch() async {
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
        viewModel.dashboardViewModel?.setMorningOutcomeValue(5, for: .globalSensation)

        await waitUntil { await repository.patchCallCount() == 1 }
        #expect(await repository.lastPatch()?.morningStates?.first?.globalSensation == 5)
    }

    @Test func patchPersistenceFailureIsNonFatalDuringMorningTap() async {
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
        viewModel.dashboardViewModel?.setMorningOutcomeValue(5, for: .globalSensation)

        await waitUntil { await repository.patchCallCount() == 1 }
        #expect(viewModel.dashboardViewModel != nil)
    }

    @Test func usesFirstPartyGraphWhenCustomGraphMissing() async {
        let firstPartyGraph = CausalGraphData(
            nodes: [
                GraphNodeElement(
                    data: GraphNodeData(
                        id: "FIRST_PARTY_NODE",
                        label: "First Party Node",
                        styleClass: "mechanism",
                        confirmed: "yes",
                        tier: 5,
                        tooltip: nil
                    )
                )
            ],
            edges: []
        )
        let repository = TrackingUserDataRepository(
            document: .empty,
            firstPartyContent: FirstPartyContentBundle(
                graphData: firstPartyGraph,
                interventionsCatalog: .empty,
                outcomesMetadata: .empty
            )
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

        #expect(viewModel.dashboardViewModel?.graphData.nodes.first?.data.id == "FIRST_PARTY_NODE")
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
    private let firstPartyContent: FirstPartyContentBundle
    private let backfillShouldThrow: Bool
    private let patchShouldThrow: Bool
    private var calls: Int = 0
    private var patchCalls: Int = 0
    private var patches: [UserDataPatch] = []

    init(
        document: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle = .empty,
        backfillShouldThrow: Bool = false,
        patchShouldThrow: Bool = false
    ) {
        self.document = document
        self.firstPartyContent = firstPartyContent
        self.backfillShouldThrow = backfillShouldThrow
        self.patchShouldThrow = patchShouldThrow
    }

    func fetch(userID: UUID) async throws -> UserDataDocument {
        _ = userID
        return document
    }

    func fetchFirstPartyContent() async throws -> FirstPartyContentBundle {
        firstPartyContent
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
        patches.append(patch)
        patchCalls += 1

        if patchShouldThrow {
            throw TrackingRepositoryError.patchFailed
        }

        return true
    }

    func patchCallCount() -> Int {
        patchCalls
    }

    func lastPatch() -> UserDataPatch? {
        patches.last
    }
}

private enum TrackingRepositoryError: Error {
    case backfillFailed
    case patchFailed
}
