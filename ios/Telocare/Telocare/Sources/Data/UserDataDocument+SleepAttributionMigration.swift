import Foundation

extension UserDataDocument {
    func withSleepAttributionMigration(
        dailyDoseProgress: [String: [String: Double]],
        nightOutcomes: [NightOutcome],
        morningStates: [MorningState],
        wakeDaySleepAttributionMigrated: Bool
    ) -> UserDataDocument {
        UserDataDocument(
            version: version,
            lastExport: lastExport,
            personalStudies: personalStudies,
            notes: notes,
            experiments: experiments,
            interventionRatings: interventionRatings,
            dailyCheckIns: dailyCheckIns,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: interventionCompletionEvents,
            interventionDoseSettings: interventionDoseSettings,
            appleHealthConnections: appleHealthConnections,
            nightExposures: nightExposures,
            nightOutcomes: nightOutcomes,
            morningStates: morningStates,
            wakeDaySleepAttributionMigrated: wakeDaySleepAttributionMigrated,
            habitTrials: habitTrials,
            habitClassifications: habitClassifications,
            activeInterventions: activeInterventions,
            hiddenInterventions: hiddenInterventions,
            unlockedAchievements: unlockedAchievements,
            customCausalDiagram: customCausalDiagram,
            experienceFlow: experienceFlow
        )
    }
}
