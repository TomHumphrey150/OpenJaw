import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published private(set) var state: RootState
    @Published private(set) var dashboardViewModel: AppViewModel?
    @Published private(set) var currentUserEmail: String?

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
    private let bootstrapSession: AuthSession?
    private let bootstrapErrorMessage: String?

    init(
        authClient: AuthClient,
        userDataRepository: UserDataRepository,
        snapshotBuilder: DashboardSnapshotBuilder,
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        accessibilityAnnouncer: AccessibilityAnnouncer,
        bootstrapSession: AuthSession? = nil,
        bootstrapErrorMessage: String? = nil
    ) {
        self.authClient = authClient
        self.userDataRepository = userDataRepository
        self.snapshotBuilder = snapshotBuilder
        self.appleHealthDoseService = appleHealthDoseService
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.bootstrapSession = bootstrapSession
        self.bootstrapErrorMessage = bootstrapErrorMessage

        state = .booting
        authEmail = ""
        authPassword = ""
        authErrorMessage = nil
        authStatusMessage = nil
        isAuthBusy = false
        currentUserEmail = nil

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
            let document = withCanonicalGraphIfMissing(fetchedDocument, fallbackGraph: fallbackGraph)
            backfillCanonicalGraphIfMissing(from: fetchedDocument, using: document)

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

        let lastModified = Self.timestampNow()
        let canonicalDiagram = CustomCausalDiagram(
            graphData: fallbackGraph,
            lastModified: lastModified
        )

        return document.withCustomCausalDiagram(canonicalDiagram)
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
