import Foundation

enum TelocareSkinID: String, CaseIterable, Sendable {
    case warmCoral = "warm-coral"
    case garden

    static let fallback: TelocareSkinID = .warmCoral

    var displayName: String {
        switch self {
        case .warmCoral:
            return "Warm Coral"
        case .garden:
            return "Garden"
        }
    }
}

struct TelocareSkinTokens: Equatable, Sendable {
    let coralHex: String
    let coralLightHex: String
    let coralDarkHex: String
    let peachHex: String
    let warmOrangeHex: String
    let sandHex: String
    let creamHex: String
    let warmGrayHex: String
    let charcoalHex: String
    let successHex: String
    let warningHex: String
    let mutedHex: String
    let robustHex: String
    let moderateHex: String
    let preliminaryHex: String
    let mechanismHex: String
    let symptomHex: String
    let interventionHex: String
    let graph: GraphSkinTokens
}

struct GraphSkinTokens: Equatable, Sendable {
    let backgroundColor: String
    let textColor: String
    let nodeBackgroundColor: String
    let nodeBorderDefaultColor: String
    let nodeBorderRobustColor: String
    let nodeBorderModerateColor: String
    let nodeBorderPreliminaryColor: String
    let nodeBorderMechanismColor: String
    let nodeBorderSymptomColor: String
    let nodeBorderInterventionColor: String
    let edgeTextBackgroundColor: String
    let tooltipBackgroundColor: String
    let tooltipBorderColor: String
    let selectionOverlayColor: String
    let edgeCausalColor: String
    let edgeProtectiveColor: String
    let edgeFeedbackColor: String
    let edgeMechanismColor: String
    let edgeInterventionColor: String
}

enum TelocareSkinCatalog {
    static func tokens(for skinID: TelocareSkinID) -> TelocareSkinTokens {
        switch skinID {
        case .warmCoral:
            return warmCoralTokens
        case .garden:
            return gardenTokens
        }
    }

    private static let warmCoralTokens = TelocareSkinTokens(
        coralHex: "#FF7060",
        coralLightHex: "#FF8C7D",
        coralDarkHex: "#E3594A",
        peachHex: "#FFDCCE",
        warmOrangeHex: "#FF9966",
        sandHex: "#FAF5EE",
        creamHex: "#FFFDF7",
        warmGrayHex: "#8C8580",
        charcoalHex: "#403B38",
        successHex: "#85C28F",
        warningHex: "#FFC75C",
        mutedHex: "#BFB8B3",
        robustHex: "#85C28F",
        moderateHex: "#FF9966",
        preliminaryHex: "#D4A5FF",
        mechanismHex: "#7DD3FC",
        symptomHex: "#FF7060",
        interventionHex: "#FF7060",
        graph: GraphSkinTokens(
            backgroundColor: "#FAF5EE",
            textColor: "#403B38",
            nodeBackgroundColor: "#FFFDF7",
            nodeBorderDefaultColor: "#BFB8B3",
            nodeBorderRobustColor: "#85C28F",
            nodeBorderModerateColor: "#FF9966",
            nodeBorderPreliminaryColor: "#D4A5FF",
            nodeBorderMechanismColor: "#7DD3FC",
            nodeBorderSymptomColor: "#FF7060",
            nodeBorderInterventionColor: "#FF7060",
            edgeTextBackgroundColor: "#FAF5EE",
            tooltipBackgroundColor: "rgba(255, 253, 247, 0.97)",
            tooltipBorderColor: "rgba(140, 133, 128, 0.4)",
            selectionOverlayColor: "#FF7060",
            edgeCausalColor: "#B45309",
            edgeProtectiveColor: "#1B4332",
            edgeFeedbackColor: "#FF9966",
            edgeMechanismColor: "#1E3A5F",
            edgeInterventionColor: "#065F46"
        )
    )

    private static let gardenTokens = TelocareSkinTokens(
        coralHex: "#5FA06B",
        coralLightHex: "#79BE86",
        coralDarkHex: "#4C8858",
        peachHex: "#E3EEDC",
        warmOrangeHex: "#8AA75E",
        sandHex: "#EEF5EA",
        creamHex: "#FCFEFA",
        warmGrayHex: "#496351",
        charcoalHex: "#1F3B2C",
        successHex: "#5FA06B",
        warningHex: "#D6A34B",
        mutedHex: "#7C9282",
        robustHex: "#5FA06B",
        moderateHex: "#8AA75E",
        preliminaryHex: "#B89CCF",
        mechanismHex: "#6EA8C8",
        symptomHex: "#D98277",
        interventionHex: "#5FA06B",
        graph: GraphSkinTokens(
            backgroundColor: "#EEF5EA",
            textColor: "#1F3B2C",
            nodeBackgroundColor: "#FDFEFB",
            nodeBorderDefaultColor: "#A7B8A8",
            nodeBorderRobustColor: "#5FA06B",
            nodeBorderModerateColor: "#8AA75E",
            nodeBorderPreliminaryColor: "#B89CCF",
            nodeBorderMechanismColor: "#6EA8C8",
            nodeBorderSymptomColor: "#D98277",
            nodeBorderInterventionColor: "#5FA06B",
            edgeTextBackgroundColor: "#EEF5EA",
            tooltipBackgroundColor: "rgba(252, 254, 250, 0.97)",
            tooltipBorderColor: "rgba(92, 118, 101, 0.35)",
            selectionOverlayColor: "#8FCB9C",
            edgeCausalColor: "#6B7F3A",
            edgeProtectiveColor: "#4F8A5C",
            edgeFeedbackColor: "#8AA75E",
            edgeMechanismColor: "#5C7F95",
            edgeInterventionColor: "#5FA06B"
        )
    )
}

enum TelocareSkinResolver {
    static func resolve(
        arguments: [String],
        environment: [String: String],
        infoDictionarySkin: String?,
        storedSkinID: TelocareSkinID?
    ) -> TelocareSkinID {
        if let value = argumentValue(arguments), let skinID = parse(value) {
            return skinID
        }

        if let value = environment["TELOCARE_SKIN"], let skinID = parse(value) {
            return skinID
        }

        if let value = infoDictionarySkin, let skinID = parse(value) {
            return skinID
        }

        if let storedSkinID {
            return storedSkinID
        }

        return .fallback
    }

    static func parse(_ rawValue: String) -> TelocareSkinID? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "warm", "warm-coral", "legacy":
            return .warmCoral
        case "garden", "relaxing-garden", "cheerful-relaxing-garden":
            return .garden
        default:
            return nil
        }
    }

    private static func argumentValue(_ arguments: [String]) -> String? {
        if let equalsArgument = arguments.first(where: { $0.hasPrefix("--skin=") }) {
            return String(equalsArgument.dropFirst("--skin=".count))
        }

        guard let optionIndex = arguments.firstIndex(of: "--skin") else {
            return nil
        }

        let valueIndex = optionIndex + 1
        guard valueIndex < arguments.count else {
            return nil
        }

        return arguments[valueIndex]
    }
}

final class SkinPreferenceStore {
    static let key = "telocare.skin.id"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> TelocareSkinID? {
        guard let rawValue = userDefaults.string(forKey: Self.key) else {
            return nil
        }

        return TelocareSkinResolver.parse(rawValue)
    }

    func save(_ skinID: TelocareSkinID) {
        userDefaults.set(skinID.rawValue, forKey: Self.key)
    }
}
