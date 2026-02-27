import Foundation
import Supabase

@MainActor
final class AppContainer {
    private let arguments: [String]
    private let environment: [String: String]
    private let bundle: Bundle
    private let skinPreferenceStore: SkinPreferenceStore
    private let museFeatureFlagStore: MuseFeatureFlagStore
    private let accessibilityAnnouncer: AccessibilityAnnouncer

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        skinPreferenceStore: SkinPreferenceStore = SkinPreferenceStore(),
        museFeatureFlagStore: MuseFeatureFlagStore = MuseFeatureFlagStore(),
        accessibilityAnnouncer: AccessibilityAnnouncer = .voiceOver
    ) {
        self.arguments = arguments
        self.environment = environment
        self.bundle = bundle
        self.skinPreferenceStore = skinPreferenceStore
        self.museFeatureFlagStore = museFeatureFlagStore
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func makeRootViewModel() -> RootViewModel {
        let snapshotBuilder = DashboardSnapshotBuilder()
        let initialSkinID = resolvedSkinID
        let initialIsMuseEnabled = resolvedIsMuseEnabled

        MuseDiagnosticsLogger.bootstrap()
        TelocareTheme.configure(skinID: initialSkinID)

        if shouldUseMockServices {
            return makeMockRootViewModel(
                snapshotBuilder: snapshotBuilder,
                initialSkinID: initialSkinID,
                initialIsMuseEnabled: initialIsMuseEnabled
            )
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
                museSessionService: defaultMuseSessionService,
                museLicenseData: configuration.museLicenseData,
                accessibilityAnnouncer: accessibilityAnnouncer,
                initialSkinID: initialSkinID,
                initialIsMuseEnabled: initialIsMuseEnabled,
                persistSkinPreference: saveSkinPreference,
                persistMuseFeatureFlag: saveMuseFeatureFlag
            )
        } catch {
            return RootViewModel(
                authClient: MockAuthClient(),
                userDataRepository: MockUserDataRepository(document: .empty),
                snapshotBuilder: snapshotBuilder,
                appleHealthDoseService: MockAppleHealthDoseService(),
                museSessionService: MockMuseSessionService(),
                museLicenseData: nil,
                accessibilityAnnouncer: accessibilityAnnouncer,
                initialSkinID: initialSkinID,
                initialIsMuseEnabled: initialIsMuseEnabled,
                persistSkinPreference: saveSkinPreference,
                persistMuseFeatureFlag: saveMuseFeatureFlag,
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

    private func makeMockRootViewModel(
        snapshotBuilder: DashboardSnapshotBuilder,
        initialSkinID: TelocareSkinID,
        initialIsMuseEnabled: Bool
    ) -> RootViewModel {
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
        let mockDocument: UserDataDocument = shouldUseEmptyMockData ? .empty : .mockForUI

        return RootViewModel(
            authClient: authClient,
            userDataRepository: MockUserDataRepository(document: mockDocument),
            snapshotBuilder: snapshotBuilder,
            appleHealthDoseService: MockAppleHealthDoseService(),
            museSessionService: MockMuseSessionService(),
            museLicenseData: nil,
            accessibilityAnnouncer: accessibilityAnnouncer,
            initialSkinID: initialSkinID,
            initialIsMuseEnabled: initialIsMuseEnabled,
            persistSkinPreference: saveSkinPreference,
            persistMuseFeatureFlag: saveMuseFeatureFlag
        )
    }

    private var resolvedSkinID: TelocareSkinID {
        let infoDictionarySkin = bundle.object(forInfoDictionaryKey: "TELOCARE_SKIN") as? String
        let storedSkinID = skinPreferenceStore.load()
        return TelocareSkinResolver.resolve(
            arguments: arguments,
            environment: environment,
            infoDictionarySkin: infoDictionarySkin,
            storedSkinID: storedSkinID
        )
    }

    private func saveSkinPreference(_ skinID: TelocareSkinID) {
        skinPreferenceStore.save(skinID)
    }

    private var resolvedIsMuseEnabled: Bool {
        if let explicitValue = boolEnvironmentValue(forKey: "TELOCARE_UI_MUSE_ENABLED") {
            return explicitValue
        }

        return museFeatureFlagStore.load()
    }

    private func saveMuseFeatureFlag(_ isEnabled: Bool) {
        museFeatureFlagStore.save(isEnabled)
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

    private var shouldUseEmptyMockData: Bool {
        environment["TELOCARE_MOCK_EMPTY_USER_DATA"] == "1"
            || arguments.contains("--mock-empty-user-data")
    }

    private var defaultMuseSessionService: MuseSessionService {
        MuseSDKGuards.defaultSessionService
    }

    private func boolEnvironmentValue(forKey key: String) -> Bool? {
        guard let rawValue = environment[key] else {
            return nil
        }

        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedValue == "1"
            || normalizedValue == "true"
            || normalizedValue == "yes"
            || normalizedValue == "on" {
            return true
        }

        if normalizedValue == "0"
            || normalizedValue == "false"
            || normalizedValue == "no"
            || normalizedValue == "off" {
            return false
        }

        return nil
    }
}
