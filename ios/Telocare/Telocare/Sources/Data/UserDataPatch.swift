import Foundation

struct UserDataPatch: Encodable, Equatable, Sendable {
    let experienceFlow: ExperienceFlow?
    let dailyCheckIns: [String: [String]]?
    let dailyDoseProgress: [String: [String: Double]]?
    let interventionDoseSettings: [String: DoseSettings]?
    let morningStates: [MorningState]?
    let hiddenInterventions: [String]?

    static func experienceFlow(_ value: ExperienceFlow) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: value,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionDoseSettings: nil,
            morningStates: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyCheckIns(_ value: [String: [String]]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: value,
            dailyDoseProgress: nil,
            interventionDoseSettings: nil,
            morningStates: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyDoseProgress(_ value: [String: [String: Double]]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: value,
            interventionDoseSettings: nil,
            morningStates: nil,
            hiddenInterventions: nil
        )
    }

    static func interventionDoseSettings(_ value: [String: DoseSettings]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionDoseSettings: value,
            morningStates: nil,
            hiddenInterventions: nil
        )
    }

    static func morningStates(_ value: [MorningState]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionDoseSettings: nil,
            morningStates: value,
            hiddenInterventions: nil
        )
    }

    static func hiddenInterventions(_ value: [String]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            dailyDoseProgress: nil,
            interventionDoseSettings: nil,
            morningStates: nil,
            hiddenInterventions: value
        )
    }
}
