import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published private(set) var state: RootState
    @Published private(set) var dashboardViewModel: AppViewModel?
    @Published private(set) var currentUserEmail: String?
    @Published private(set) var selectedSkinID: TelocareSkinID
    @Published private(set) var isMuseEnabled: Bool

    @Published var authEmail: String
    @Published var authPassword: String
    @Published private(set) var authErrorMessage: String?
    @Published private(set) var authStatusMessage: String?
    @Published private(set) var isAuthBusy: Bool

    private let authClient: AuthClient
    private let sessionHydrationUseCase: SessionHydrationUseCase
    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private let persistSkinPreference: (TelocareSkinID) -> Void
    private let persistMuseFeatureFlag: (Bool) -> Void
    private let bootstrapSession: AuthSession?
    private let bootstrapErrorMessage: String?

    init(
        authClient: AuthClient,
        userDataRepository: UserDataRepository,
        snapshotBuilder: DashboardSnapshotBuilder,
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        museSessionService: MuseSessionService = MockMuseSessionService(),
        museLicenseData: Data? = nil,
        accessibilityAnnouncer: AccessibilityAnnouncer,
        initialSkinID: TelocareSkinID = .warmCoral,
        initialIsMuseEnabled: Bool = false,
        persistSkinPreference: @escaping (TelocareSkinID) -> Void = { _ in },
        persistMuseFeatureFlag: @escaping (Bool) -> Void = { _ in },
        bootstrapSession: AuthSession? = nil,
        bootstrapErrorMessage: String? = nil,
        sessionHydrationUseCase: SessionHydrationUseCase? = nil
    ) {
        self.authClient = authClient
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.persistSkinPreference = persistSkinPreference
        self.persistMuseFeatureFlag = persistMuseFeatureFlag
        self.bootstrapSession = bootstrapSession
        self.bootstrapErrorMessage = bootstrapErrorMessage

        if let sessionHydrationUseCase {
            self.sessionHydrationUseCase = sessionHydrationUseCase
        } else {
            let dashboardFactory = DefaultRootDashboardFactory(
                snapshotBuilder: snapshotBuilder,
                userDataRepository: userDataRepository,
                appleHealthDoseService: appleHealthDoseService,
                museSessionService: museSessionService,
                museLicenseData: museLicenseData,
                accessibilityAnnouncer: accessibilityAnnouncer
            )
            self.sessionHydrationUseCase = DefaultSessionHydrationUseCase(
                userDataRepository: userDataRepository,
                migrationPipeline: DefaultUserDataMigrationPipeline(),
                dashboardFactory: dashboardFactory
            )
        }

        state = .booting
        authEmail = ""
        authPassword = ""
        authErrorMessage = nil
        authStatusMessage = nil
        isAuthBusy = false
        currentUserEmail = nil
        selectedSkinID = initialSkinID
        isMuseEnabled = initialIsMuseEnabled

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

    func setMuseEnabled(_ isEnabled: Bool) {
        guard isMuseEnabled != isEnabled else {
            return
        }

        isMuseEnabled = isEnabled
        persistMuseFeatureFlag(isEnabled)
        if isEnabled {
            accessibilityAnnouncer.announce("Muse controls enabled.")
            return
        }

        dashboardViewModel?.dismissMuseFitCalibration()
        if dashboardViewModel?.museCanStopRecording == true {
            dashboardViewModel?.stopMuseRecording()
        }
        if dashboardViewModel?.museCanDisconnect == true {
            dashboardViewModel?.disconnectMuseHeadband()
        }
        accessibilityAnnouncer.announce("Muse controls hidden.")
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
            let hydration = try await sessionHydrationUseCase.hydrate(session: session)
            dashboardViewModel = hydration.dashboardViewModel
            currentUserEmail = hydration.currentUserEmail
            state = .ready
            accessibilityAnnouncer.announce("Signed in. Dashboard ready.")
            if let dashboardViewModel {
                Task {
                    await dashboardViewModel.refreshAllConnectedAppleHealth(trigger: .automatic)
                }
            }
        } catch {
            dashboardViewModel = nil
            state = .fatal(message: "Failed to load required data from Supabase.")
            accessibilityAnnouncer.announce("Failed to load required data from Supabase.")
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
