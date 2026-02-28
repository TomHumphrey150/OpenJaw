import Foundation

@MainActor
protocol RootDashboardFactory {
    func makeDashboard(
        document: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle,
        fallbackGraph: CausalGraphData
    ) -> AppViewModel
}

@MainActor
struct DefaultRootDashboardFactory: RootDashboardFactory {
    private let snapshotBuilder: DashboardSnapshotBuilder
    private let userDataRepository: UserDataRepository
    private let appleHealthDoseService: AppleHealthDoseService
    private let museSessionService: MuseSessionService
    private let museLicenseData: Data?
    private let accessibilityAnnouncer: AccessibilityAnnouncer

    init(
        snapshotBuilder: DashboardSnapshotBuilder,
        userDataRepository: UserDataRepository,
        appleHealthDoseService: AppleHealthDoseService,
        museSessionService: MuseSessionService,
        museLicenseData: Data?,
        accessibilityAnnouncer: AccessibilityAnnouncer
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.userDataRepository = userDataRepository
        self.appleHealthDoseService = appleHealthDoseService
        self.museSessionService = museSessionService
        self.museLicenseData = museLicenseData
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func makeDashboard(
        document: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle,
        fallbackGraph: CausalGraphData
    ) -> AppViewModel {
        let snapshot = snapshotBuilder.build(
            from: document,
            firstPartyContent: firstPartyContent,
            now: Date()
        )
        let graphData = snapshotBuilder.graphData(
            from: document,
            fallbackGraph: fallbackGraph
        )

        return AppViewModel(
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
            initialProgressQuestionSetState: document.progressQuestionSetState,
            initialGardenAliasOverrides: document.gardenAliasOverrides,
            initialCustomCausalDiagram: document.customCausalDiagram,
            initialActiveInterventions: document.activeInterventions,
            persistUserDataPatch: { patch in
                try await userDataRepository.upsertUserDataPatch(patch)
            },
            appleHealthDoseService: appleHealthDoseService,
            museSessionService: museSessionService,
            museLicenseData: museLicenseData,
            accessibilityAnnouncer: accessibilityAnnouncer
        )
    }
}
