import Foundation

struct UserDataPatch: Encodable, Equatable, Sendable {
    let experienceFlow: ExperienceFlow?
    let dailyCheckIns: [String: [String]]?
    let dailyDoseProgress: [String: [String: Double]]?
    let interventionCompletionEvents: [InterventionCompletionEvent]?
    let interventionDoseSettings: [String: DoseSettings]?
    let appleHealthConnections: [String: AppleHealthConnection]?
    let nightOutcomes: [NightOutcome]?
    let morningStates: [MorningState]?
    let foundationCheckIns: [FoundationCheckIn]?
    let userDefinedPillars: [UserDefinedPillar]?
    let pillarAssignments: [PillarAssignment]?
    let pillarCheckIns: [PillarCheckIn]?
    let activeInterventions: [String]?
    let hiddenInterventions: [String]?
    let customCausalDiagram: CustomCausalDiagram?
    let wakeDaySleepAttributionMigrated: Bool?
    let progressQuestionSetState: ProgressQuestionSetState?
    let gardenAliasOverrides: [GardenAliasOverride]?
    let plannerPreferencesState: PlannerPreferencesState?
    let habitPlannerState: HabitPlannerState?
    let healthLensState: HealthLensState?
    let globalLensSelection: HealthLensState?

    init(
        experienceFlow: ExperienceFlow?,
        dailyCheckIns: [String: [String]]?,
        dailyDoseProgress: [String: [String: Double]]?,
        interventionCompletionEvents: [InterventionCompletionEvent]?,
        interventionDoseSettings: [String: DoseSettings]?,
        appleHealthConnections: [String: AppleHealthConnection]?,
        nightOutcomes: [NightOutcome]? = nil,
        morningStates: [MorningState]?,
        foundationCheckIns: [FoundationCheckIn]? = nil,
        userDefinedPillars: [UserDefinedPillar]? = nil,
        pillarAssignments: [PillarAssignment]? = nil,
        pillarCheckIns: [PillarCheckIn]? = nil,
        activeInterventions: [String]?,
        hiddenInterventions: [String]?,
        customCausalDiagram: CustomCausalDiagram? = nil,
        wakeDaySleepAttributionMigrated: Bool? = nil,
        progressQuestionSetState: ProgressQuestionSetState? = nil,
        gardenAliasOverrides: [GardenAliasOverride]? = nil,
        plannerPreferencesState: PlannerPreferencesState? = nil,
        habitPlannerState: HabitPlannerState? = nil,
        healthLensState: HealthLensState? = nil,
        globalLensSelection: HealthLensState? = nil
    ) {
        self.experienceFlow = experienceFlow
        self.dailyCheckIns = dailyCheckIns
        self.dailyDoseProgress = dailyDoseProgress
        self.interventionCompletionEvents = interventionCompletionEvents
        self.interventionDoseSettings = interventionDoseSettings
        self.appleHealthConnections = appleHealthConnections
        self.nightOutcomes = nightOutcomes
        self.morningStates = morningStates
        self.foundationCheckIns = foundationCheckIns
        self.userDefinedPillars = userDefinedPillars
        self.pillarAssignments = pillarAssignments
        self.pillarCheckIns = pillarCheckIns
        self.activeInterventions = activeInterventions
        self.hiddenInterventions = hiddenInterventions
        self.customCausalDiagram = customCausalDiagram
        self.wakeDaySleepAttributionMigrated = wakeDaySleepAttributionMigrated
        self.progressQuestionSetState = progressQuestionSetState
        self.gardenAliasOverrides = gardenAliasOverrides
        self.plannerPreferencesState = plannerPreferencesState
        self.habitPlannerState = habitPlannerState
        self.healthLensState = healthLensState
        self.globalLensSelection = globalLensSelection
    }

    static func experienceFlow(_ value: ExperienceFlow) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: value,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyCheckIns(_ value: [String: [String]]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: value,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyDoseProgress(_ value: [String: [String: Double]]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: value,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func interventionCompletionEvents(_ value: [InterventionCompletionEvent]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: value,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyCheckInsAndCompletionEvents(
        _ dailyCheckIns: [String: [String]],
        _ completionEvents: [InterventionCompletionEvent]
    ) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: dailyCheckIns,
            dailyDoseProgress: nil,
            interventionCompletionEvents: completionEvents,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyDoseProgressAndCompletionEvents(
        _ dailyDoseProgress: [String: [String: Double]],
        _ completionEvents: [InterventionCompletionEvent]
    ) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: completionEvents,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func interventionDoseSettings(_ value: [String: DoseSettings]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: value,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func appleHealthConnections(_ value: [String: AppleHealthConnection]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: value,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func appleHealthConnectionsAndDailyDoseProgress(
        _ appleHealthConnections: [String: AppleHealthConnection],
        _ dailyDoseProgress: [String: [String: Double]]
    ) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: appleHealthConnections,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func morningStates(_ value: [MorningState]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: value,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func nightOutcomes(_ value: [NightOutcome]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            nightOutcomes: value,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func foundationCheckIns(_ value: [FoundationCheckIn]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            foundationCheckIns: value,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func sleepAttributionMigration(
        dailyDoseProgress: [String: [String: Double]],
        nightOutcomes: [NightOutcome],
        morningStates: [MorningState]
    ) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            nightOutcomes: nightOutcomes,
            morningStates: morningStates,
            activeInterventions: nil,
            hiddenInterventions: nil,
            wakeDaySleepAttributionMigrated: true
        )
    }

    static func activeInterventions(_ value: [String]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: value,
            hiddenInterventions: nil
        )
    }

    static func hiddenInterventions(_ value: [String]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: value
        )
    }

    static func customCausalDiagram(_ value: CustomCausalDiagram) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            customCausalDiagram: value
        )
    }

    static func customCausalDiagramAndGardenAliasOverrides(
        _ diagram: CustomCausalDiagram,
        _ aliases: [GardenAliasOverride]
    ) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            customCausalDiagram: diagram,
            gardenAliasOverrides: aliases
        )
    }

    static func progressQuestionSetState(_ value: ProgressQuestionSetState) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            progressQuestionSetState: value
        )
    }

    static func plannerPreferencesState(_ value: PlannerPreferencesState) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            plannerPreferencesState: value
        )
    }

    static func habitPlannerState(_ value: HabitPlannerState) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            habitPlannerState: value
        )
    }

    static func healthLensState(_ value: HealthLensState) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            healthLensState: value,
            globalLensSelection: value
        )
    }

    static func globalLensSelection(_ value: HealthLensState) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            activeInterventions: nil,
            hiddenInterventions: nil,
            globalLensSelection: value
        )
    }

    static func userDefinedPillars(_ value: [UserDefinedPillar]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            userDefinedPillars: value,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func pillarAssignments(_ value: [PillarAssignment]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            pillarAssignments: value,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }

    static func pillarCheckIns(_ value: [PillarCheckIn]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionCompletionEvents: nil,
            interventionDoseSettings: nil,
            appleHealthConnections: nil,
            morningStates: nil,
            pillarCheckIns: value,
            activeInterventions: nil,
            hiddenInterventions: nil
        )
    }
}
