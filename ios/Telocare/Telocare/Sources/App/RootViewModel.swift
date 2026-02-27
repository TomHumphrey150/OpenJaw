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
    private let userDataRepository: UserDataRepository
    private let snapshotBuilder: DashboardSnapshotBuilder
    private let appleHealthDoseService: AppleHealthDoseService
    private let museSessionService: MuseSessionService
    private let museLicenseData: Data?
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
        bootstrapErrorMessage: String? = nil
    ) {
        self.authClient = authClient
        self.userDataRepository = userDataRepository
        self.snapshotBuilder = snapshotBuilder
        self.appleHealthDoseService = appleHealthDoseService
        self.museSessionService = museSessionService
        self.museLicenseData = museLicenseData
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.persistSkinPreference = persistSkinPreference
        self.persistMuseFeatureFlag = persistMuseFeatureFlag
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
            let fetchedDocument = try await userDataRepository.fetch(userID: session.userID)
            let firstPartyContent = await loadFirstPartyContent()
            let fallbackGraph = firstPartyContent.graphData ?? CanonicalGraphLoader.loadGraphOrFallback()
            let hydratedDocument = withCanonicalGraphIfMissing(fetchedDocument, fallbackGraph: fallbackGraph)
            let graphMigratedDocument = withLegacyDormantGraphDeactivationMigrationIfNeeded(hydratedDocument)
            let document = withWakeDaySleepAttributionMigrationIfNeeded(
                graphMigratedDocument,
                interventionsCatalog: firstPartyContent.interventionsCatalog
            )
            backfillCanonicalGraphIfMissing(from: fetchedDocument, using: document)
            persistLegacyDormantGraphMigrationIfNeeded(
                from: fetchedDocument,
                hydrated: hydratedDocument,
                migrated: graphMigratedDocument
            )
            persistWakeDaySleepAttributionMigrationIfNeeded(
                from: graphMigratedDocument,
                migrated: document
            )

            let snapshot = snapshotBuilder.build(
                from: document,
                firstPartyContent: firstPartyContent,
                now: Date()
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
                initialNightOutcomes: document.nightOutcomes,
                initialMorningStates: document.morningStates,
                initialMorningQuestionnaire: document.morningQuestionnaire,
                initialActiveInterventions: document.activeInterventions,
                persistUserDataPatch: { patch in
                    try await repository.upsertUserDataPatch(patch)
                },
                appleHealthDoseService: appleHealthDoseService,
                museSessionService: museSessionService,
                museLicenseData: museLicenseData,
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

    private func withWakeDaySleepAttributionMigrationIfNeeded(
        _ document: UserDataDocument,
        interventionsCatalog: InterventionsCatalog
    ) -> UserDataDocument {
        guard !document.wakeDaySleepAttributionMigrated else {
            return document
        }

        let sleepInterventionIDs = Self.sleepInterventionIDs(
            from: interventionsCatalog
        )
        let migratedDailyDoseProgress = Self.shiftSleepDoseProgress(
            document.dailyDoseProgress,
            sleepInterventionIDs: sleepInterventionIDs
        )
        let migratedNightOutcomes = Self.shiftNightOutcomes(document.nightOutcomes)
        let migratedMorningStates = Self.shiftMorningStates(document.morningStates)

        let hasChanges =
            migratedDailyDoseProgress != document.dailyDoseProgress
            || migratedNightOutcomes != document.nightOutcomes
            || migratedMorningStates != document.morningStates
        guard hasChanges else {
            return document
        }

        return document.withSleepAttributionMigration(
            dailyDoseProgress: migratedDailyDoseProgress,
            nightOutcomes: migratedNightOutcomes,
            morningStates: migratedMorningStates,
            wakeDaySleepAttributionMigrated: true
        )
    }

    private func persistWakeDaySleepAttributionMigrationIfNeeded(
        from fetched: UserDataDocument,
        migrated: UserDataDocument
    ) {
        guard
            fetched.wakeDaySleepAttributionMigrated != migrated.wakeDaySleepAttributionMigrated
            || fetched.dailyDoseProgress != migrated.dailyDoseProgress
            || fetched.nightOutcomes != migrated.nightOutcomes
            || fetched.morningStates != migrated.morningStates
        else {
            return
        }

        let repository = userDataRepository
        Task.detached {
            do {
                _ = try await repository.upsertUserDataPatch(
                    .sleepAttributionMigration(
                        dailyDoseProgress: migrated.dailyDoseProgress,
                        nightOutcomes: migrated.nightOutcomes,
                        morningStates: migrated.morningStates
                    )
                )
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
                    isDeactivated: true,
                    parentIds: node.data.parentIds,
                    parentId: node.data.parentId,
                    isExpanded: node.data.isExpanded
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

    private static func sleepInterventionIDs(from catalog: InterventionsCatalog) -> Set<String> {
        Set(
            catalog.interventions.compactMap { intervention in
                guard let config = intervention.appleHealthConfig else {
                    return nil
                }

                if config.identifier == .sleepAnalysis {
                    return intervention.id
                }

                if config.dayAttribution == .previousNightNoonCutoff {
                    return intervention.id
                }

                return nil
            }
        )
    }

    private static func shiftSleepDoseProgress(
        _ dailyDoseProgress: [String: [String: Double]],
        sleepInterventionIDs: Set<String>
    ) -> [String: [String: Double]] {
        guard !sleepInterventionIDs.isEmpty else {
            return dailyDoseProgress
        }

        var migrated = dailyDoseProgress

        for (dateKey, dosesByIntervention) in dailyDoseProgress {
            let shiftedDateKey = shiftedDateKeyByOneDay(dateKey)
            guard shiftedDateKey != dateKey else {
                continue
            }

            let sleepEntries = dosesByIntervention.filter { sleepInterventionIDs.contains($0.key) }
            guard !sleepEntries.isEmpty else {
                continue
            }

            var sourceDoses = migrated[dateKey] ?? [:]
            var targetDoses = migrated[shiftedDateKey] ?? [:]

            for (interventionID, value) in sleepEntries {
                sourceDoses.removeValue(forKey: interventionID)
                let existingValue = targetDoses[interventionID] ?? 0
                targetDoses[interventionID] = max(existingValue, value)
            }

            if sourceDoses.isEmpty {
                migrated.removeValue(forKey: dateKey)
            } else {
                migrated[dateKey] = sourceDoses
            }
            migrated[shiftedDateKey] = targetDoses
        }

        return migrated
    }

    private static func shiftNightOutcomes(_ nightOutcomes: [NightOutcome]) -> [NightOutcome] {
        var outcomesByNightID: [String: NightOutcome] = [:]

        for outcome in nightOutcomes {
            let shiftedNightID = shiftedDateKeyByOneDay(outcome.nightId)
            guard shiftedNightID != outcome.nightId else {
                outcomesByNightID[outcome.nightId] = preferredNightOutcome(
                    existing: outcomesByNightID[outcome.nightId],
                    candidate: outcome
                )
                continue
            }

            let shiftedOutcome = NightOutcome(
                nightId: shiftedNightID,
                microArousalCount: outcome.microArousalCount,
                microArousalRatePerHour: outcome.microArousalRatePerHour,
                confidence: outcome.confidence,
                totalSleepMinutes: outcome.totalSleepMinutes,
                source: outcome.source,
                createdAt: outcome.createdAt
            )
            outcomesByNightID[shiftedNightID] = preferredNightOutcome(
                existing: outcomesByNightID[shiftedNightID],
                candidate: shiftedOutcome
            )
        }

        return outcomesByNightID.values.sorted { $0.nightId > $1.nightId }
    }

    private static func preferredNightOutcome(
        existing: NightOutcome?,
        candidate: NightOutcome
    ) -> NightOutcome {
        guard let existing else {
            return candidate
        }

        if candidate.createdAt >= existing.createdAt {
            return candidate
        }

        return existing
    }

    private static func shiftMorningStates(_ morningStates: [MorningState]) -> [MorningState] {
        var statesByNightID: [String: MorningState] = [:]

        for state in morningStates {
            let shiftedNightID = shiftedDateKeyByOneDay(state.nightId)
            guard shiftedNightID != state.nightId else {
                statesByNightID[state.nightId] = preferredMorningState(
                    existing: statesByNightID[state.nightId],
                    candidate: state
                )
                continue
            }

            let shiftedState = MorningState(
                nightId: shiftedNightID,
                globalSensation: state.globalSensation,
                neckTightness: state.neckTightness,
                jawSoreness: state.jawSoreness,
                earFullness: state.earFullness,
                healthAnxiety: state.healthAnxiety,
                stressLevel: state.stressLevel,
                createdAt: state.createdAt
            )
            statesByNightID[shiftedNightID] = preferredMorningState(
                existing: statesByNightID[shiftedNightID],
                candidate: shiftedState
            )
        }

        return statesByNightID.values.sorted { $0.nightId > $1.nightId }
    }

    private static func preferredMorningState(
        existing: MorningState?,
        candidate: MorningState
    ) -> MorningState {
        guard let existing else {
            return candidate
        }

        if candidate.createdAt >= existing.createdAt {
            return candidate
        }

        return existing
    }

    private static func shiftedDateKeyByOneDay(_ dateKey: String) -> String {
        let parts = dateKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return dateKey
        }
        guard
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return dateKey
        }

        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return dateKey
        }
        guard let shiftedDate = calendar.date(byAdding: .day, value: 1, to: date) else {
            return dateKey
        }

        let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shiftedDate)
        guard
            let shiftedYear = shiftedComponents.year,
            let shiftedMonth = shiftedComponents.month,
            let shiftedDay = shiftedComponents.day
        else {
            return dateKey
        }

        return String(format: "%04d-%02d-%02d", shiftedYear, shiftedMonth, shiftedDay)
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
