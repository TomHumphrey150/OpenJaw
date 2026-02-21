import Foundation

struct UserDataPatch: Encodable, Equatable, Sendable {
    let experienceFlow: ExperienceFlow?

    static func experienceFlow(_ value: ExperienceFlow) -> UserDataPatch {
        UserDataPatch(experienceFlow: value)
    }
}
