import Foundation

struct UserDataPatch: Encodable, Equatable, Sendable {
    let experienceFlow: ExperienceFlow?
    let dailyCheckIns: [String: [String]]?
    let dailyDoseProgress: [String: [String: Double]]?
    let interventionCompletionEvents: [InterventionCompletionEvent]?
    let interventionDoseSettings: [String: DoseSettings]?
    let appleHealthConnections: [String: AppleHealthConnection]?
    let morningStates: [MorningState]?
    let activeInterventions: [String]?
    let hiddenInterventions: [String]?

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
}
