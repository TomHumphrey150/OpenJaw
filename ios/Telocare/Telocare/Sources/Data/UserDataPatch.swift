import Foundation

struct UserDataPatch: Encodable, Equatable, Sendable {
    let experienceFlow: ExperienceFlow?
    let dailyCheckIns: [String: [String]]?
    let morningStates: [MorningState]?
    let hiddenInterventions: [String]?

    static func experienceFlow(_ value: ExperienceFlow) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: value,
            dailyCheckIns: nil,
            morningStates: nil,
            hiddenInterventions: nil
        )
    }

    static func dailyCheckIns(_ value: [String: [String]]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: value,
            morningStates: nil,
            hiddenInterventions: nil
        )
    }

    static func morningStates(_ value: [MorningState]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            morningStates: value,
            hiddenInterventions: nil
        )
    }

    static func hiddenInterventions(_ value: [String]) -> UserDataPatch {
        UserDataPatch(
            experienceFlow: nil,
            dailyCheckIns: nil,
            morningStates: nil,
            hiddenInterventions: value
        )
    }
}
