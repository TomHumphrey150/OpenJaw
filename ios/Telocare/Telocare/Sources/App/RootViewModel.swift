import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published private(set) var state: RootState
    @Published private(set) var dashboardViewModel: AppViewModel?
    @Published private(set) var currentUserEmail: String?
    @Published private(set) var selectedSkinID: TelocareSkinID

    @Published var authEmail: String
    @Published var authPassword: String
    @Published private(set) var authErrorMessage: String?
    @Published private(set) var authStatusMessage: String?
    @Published private(set) var isAuthBusy: Bool

    private let authClient: AuthClient
    private let userDataRepository: UserDataRepository
    private let snapshotBuilder: DashboardSnapshotBuilder
    private let appleHealthDoseService: AppleHealthDoseService
    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private let persistSkinPreference: (TelocareSkinID) -> Void
    private let bootstrapSession: AuthSession?
    private let bootstrapErrorMessage: String?

    init(
        authClient: AuthClient,
        userDataRepository: UserDataRepository,
        snapshotBuilder: DashboardSnapshotBuilder,
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        accessibilityAnnouncer: AccessibilityAnnouncer,
        initialSkinID: TelocareSkinID = .warmCoral,
        persistSkinPreference: @escaping (TelocareSkinID) -> Void = { _ in },
        bootstrapSession: AuthSession? = nil,
        bootstrapErrorMessage: String? = nil
    ) {
        self.authClient = authClient
        self.userDataRepository = userDataRepository
        self.snapshotBuilder = snapshotBuilder
        self.appleHealthDoseService = appleHealthDoseService
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.persistSkinPreference = persistSkinPreference
        self.bootstrapSession = bootstrapSession
        self.bootstrapErrorMessage = bootstrapErrorMessage

        state = .booting
        authEmail = ""
        authPassword = ""
        authErrorMessage = nil
        authStatusMessage = nil
        isAuthBusy = false
        currentUserEmail = nil
        selectedSkinID = initialSkinID

        TelocareTheme.configure(skinID: initialSkinID)

        Task {
            await bootstrap()
        }
    }

    func submitSignIn() {
        Task {
            await signIn()
        }
    }

    func submitSignUp() {
        Task {
            await signUp()
        }
    }

    func signOut() {
        Task {
            do {
                try await authClient.signOut()
            } catch {
            }

            resetToAuthState()
        }
    }

    func setSkin(_ skinID: TelocareSkinID) {
        guard selectedSkinID != skinID else {
            return
        }

        TelocareTheme.configure(skinID: skinID)
        selectedSkinID = skinID
        persistSkinPreference(skinID)
        accessibilityAnnouncer.announce("Theme changed to \(skinID.displayName).")
    }

    private func bootstrap() async {
        if let bootstrapErrorMessage {
            state = .fatal(message: bootstrapErrorMessage)
            accessibilityAnnouncer.announce(bootstrapErrorMessage)
            return
        }

        if let bootstrapSession {
            await hydrate(session: bootstrapSession)
            return
        }

        if let session = await authClient.currentSession() {
            await hydrate(session: session)
            return
        }

        state = .auth
    }

    private func signIn() async {
        guard state == .auth else {
            return
        }

        authErrorMessage = nil
        authStatusMessage = nil
        isAuthBusy = true

        do {
            let session = try await authClient.signIn(email: authEmail, password: authPassword)
            await hydrate(session: session)
        } catch {
            isAuthBusy = false
            state = .auth
            authErrorMessage = AuthErrorMessageMapper.message(for: error, operation: .signIn)
            accessibilityAnnouncer.announce(authErrorMessage ?? "Authentication failed.")
        }
    }

    private func signUp() async {
        guard state == .auth else {
            return
        }

        authErrorMessage = nil
        authStatusMessage = nil
        isAuthBusy = true

        do {
            let result = try await authClient.signUp(email: authEmail, password: authPassword)
            switch result {
            case .authenticated(let session):
                await hydrate(session: session)
            case .needsEmailConfirmation:
                isAuthBusy = false
                state = .auth
                authStatusMessage = "Account created. If email confirmation is enabled, check your inbox before signing in."
                accessibilityAnnouncer.announce(authStatusMessage ?? "Account created.")
            }
        } catch {
            isAuthBusy = false
            state = .auth
            authErrorMessage = AuthErrorMessageMapper.message(for: error, operation: .signUp)
            accessibilityAnnouncer.announce(authErrorMessage ?? "Account creation failed.")
        }
    }

    private func hydrate(session: AuthSession) async {
        state = .hydrating
        isAuthBusy = false
        authErrorMessage = nil
        authStatusMessage = nil

        do {
            let fetchedDocument = try await userDataRepository.fetch(userID: session.userID)
            let firstPartyContent = await loadFirstPartyContent()
            let fallbackGraph = firstPartyContent.graphData ?? CanonicalGraphLoader.loadGraphOrFallback()
            let hydratedDocument = withCanonicalGraphIfMissing(fetchedDocument, fallbackGraph: fallbackGraph)
            let document = withLegacyDormantGraphDeactivationMigrationIfNeeded(hydratedDocument)
            backfillCanonicalGraphIfMissing(from: fetchedDocument, using: document)
            persistLegacyDormantGraphMigrationIfNeeded(
                from: fetchedDocument,
                hydrated: hydratedDocument,
                migrated: document
            )

            let snapshot = snapshotBuilder.build(
                from: document,
                firstPartyContent: firstPartyContent
            )
            let graphData = snapshotBuilder.graphData(
                from: document,
                fallbackGraph: fallbackGraph
            )
            let repository = userDataRepository
            dashboardViewModel = AppViewModel(
                snapshot: snapshot,
                graphData: graphData,
                initialExperienceFlow: document.experienceFlow,
                initialDailyCheckIns: document.dailyCheckIns,
                initialDailyDoseProgress: document.dailyDoseProgress,
                initialInterventionCompletionEvents: document.interventionCompletionEvents,
                initialInterventionDoseSettings: document.interventionDoseSettings,
                initialAppleHealthConnections: document.appleHealthConnections,
                initialMorningStates: document.morningStates,
                initialActiveInterventions: document.activeInterventions,
                persistUserDataPatch: { patch in
                    try await repository.upsertUserDataPatch(patch)
                },
                appleHealthDoseService: appleHealthDoseService,
                accessibilityAnnouncer: accessibilityAnnouncer
            )
            currentUserEmail = session.email
            state = .ready
            accessibilityAnnouncer.announce("Signed in. Dashboard ready.")
            if let dashboardViewModel {
                Task {
                    await dashboardViewModel.refreshAllConnectedAppleHealth(trigger: .automatic)
                }
            }
        } catch {
            dashboardViewModel = nil
            state = .fatal(message: "Failed to load user data from Supabase.")
            accessibilityAnnouncer.announce("Failed to load user data from Supabase.")
        }
    }

    private func withCanonicalGraphIfMissing(
        _ document: UserDataDocument,
        fallbackGraph: CausalGraphData
    ) -> UserDataDocument {
        guard document.customCausalDiagram == nil else {
            return document
        }

        let graphData = Self.seedLegacyDormantGraphDeactivationIfNeeded(fallbackGraph) ?? fallbackGraph
        let lastModified = Self.timestampNow()
        let canonicalDiagram = CustomCausalDiagram(
            graphData: graphData,
            lastModified: lastModified
        )

        return document.withCustomCausalDiagram(canonicalDiagram)
    }

    private func withLegacyDormantGraphDeactivationMigrationIfNeeded(_ document: UserDataDocument) -> UserDataDocument {
        guard let customCausalDiagram = document.customCausalDiagram else {
            return document
        }

        guard let migratedGraphData = Self.seedLegacyDormantGraphDeactivationIfNeeded(customCausalDiagram.graphData) else {
            return document
        }

        let migratedDiagram = CustomCausalDiagram(
            graphData: migratedGraphData,
            lastModified: Self.timestampNow()
        )
        return document.withCustomCausalDiagram(migratedDiagram)
    }

    private func backfillCanonicalGraphIfMissing(from fetched: UserDataDocument, using hydrated: UserDataDocument) {
        guard fetched.customCausalDiagram == nil else {
            return
        }

        guard let canonicalDiagram = hydrated.customCausalDiagram else {
            return
        }

        let repository = userDataRepository
        Task.detached {
            do {
                _ = try await repository.backfillDefaultGraphIfMissing(
                    canonicalGraph: canonicalDiagram.graphData,
                    lastModified: canonicalDiagram.lastModified ?? Self.timestampNow()
                )
            } catch {
            }
        }
    }

    private func persistLegacyDormantGraphMigrationIfNeeded(
        from fetched: UserDataDocument,
        hydrated: UserDataDocument,
        migrated: UserDataDocument
    ) {
        guard fetched.customCausalDiagram != nil else {
            return
        }

        guard hydrated.customCausalDiagram != migrated.customCausalDiagram else {
            return
        }

        guard let migratedDiagram = migrated.customCausalDiagram else {
            return
        }

        let repository = userDataRepository
        Task.detached {
            do {
                _ = try await repository.upsertUserDataPatch(.customCausalDiagram(migratedDiagram))
            } catch {
            }
        }
    }

    private static func seedLegacyDormantGraphDeactivationIfNeeded(_ graphData: CausalGraphData) -> CausalGraphData? {
        if hasExplicitGraphDeactivationState(graphData) {
            return nil
        }

        let dormantNodeIDs = Set(
            graphData.nodes
                .map(\.data)
                .filter(isLegacyDormantNode)
                .map(\.id)
        )

        guard !dormantNodeIDs.isEmpty else {
            return nil
        }

        let nextNodes = graphData.nodes.map { node in
            guard dormantNodeIDs.contains(node.data.id) else {
                return node
            }

            return GraphNodeElement(
                data: GraphNodeData(
                    id: node.data.id,
                    label: node.data.label,
                    styleClass: node.data.styleClass,
                    confirmed: node.data.confirmed,
                    tier: node.data.tier,
                    tooltip: node.data.tooltip,
                    isDeactivated: true
                )
            )
        }

        let nextEdges = graphData.edges.map { edge in
            guard dormantNodeIDs.contains(edge.data.source) || dormantNodeIDs.contains(edge.data.target) else {
                return edge
            }

            return GraphEdgeElement(
                data: GraphEdgeData(
                    source: edge.data.source,
                    target: edge.data.target,
                    label: edge.data.label,
                    edgeType: edge.data.edgeType,
                    edgeColor: edge.data.edgeColor,
                    tooltip: edge.data.tooltip,
                    isDeactivated: true
                )
            )
        }

        return CausalGraphData(
            nodes: nextNodes,
            edges: nextEdges
        )
    }

    private static func hasExplicitGraphDeactivationState(_ graphData: CausalGraphData) -> Bool {
        if graphData.nodes.contains(where: { $0.data.isDeactivated != nil }) {
            return true
        }

        return graphData.edges.contains(where: { $0.data.isDeactivated != nil })
    }

    private static func isLegacyDormantNode(_ node: GraphNodeData) -> Bool {
        guard let confirmed = node.confirmed?.lowercased() else {
            return false
        }

        return confirmed == "no" || confirmed == "inactive" || confirmed == "external"
    }

    nonisolated private static func timestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func loadFirstPartyContent() async -> FirstPartyContentBundle {
        do {
            return try await userDataRepository.fetchFirstPartyContent()
        } catch {
            return .empty
        }
    }

    private func resetToAuthState() {
        dashboardViewModel = nil
        currentUserEmail = nil
        authEmail = ""
        authPassword = ""
        authErrorMessage = nil
        authStatusMessage = nil
        isAuthBusy = false
        state = .auth
        accessibilityAnnouncer.announce("Signed out.")
    }
}
