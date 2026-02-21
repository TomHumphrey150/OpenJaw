import Foundation

struct UserDataPatch: Encodable, Equatable, Sendable {
    let experienceFlow: ExperienceFlow?
    let morningStates: [MorningState]?

    static func experienceFlow(_ value: ExperienceFlow) -> UserDataPatch {
        UserDataPatch(experienceFlow: value, morningStates: nil)
    }

    static func morningStates(_ value: [MorningState]) -> UserDataPatch {
        UserDataPatch(experienceFlow: nil, morningStates: value)
    }
}
