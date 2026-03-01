import Foundation

struct FoundationCheckInScale {
    static let minimumValue = 1
    static let maximumValue = 4
    static let options = [1, 2, 3, 4]
    static let questionSetVersionPrefix = "questions-pillars-v2-"

    static func isValid(value: Int) -> Bool {
        (minimumValue...maximumValue).contains(value)
    }

    static func emoji(for value: Int) -> String {
        switch value {
        case 1:
            return "😫"
        case 2:
            return "😕"
        case 3:
            return "🙂"
        case 4:
            return "😄"
        default:
            return "😐"
        }
    }

    static func questionSetVersion(for graphVersion: String) -> String {
        "\(questionSetVersionPrefix)\(graphVersion)"
    }

    static func usesCurrentQuestionSetVersion(_ version: String) -> Bool {
        version.hasPrefix(questionSetVersionPrefix)
    }
}
