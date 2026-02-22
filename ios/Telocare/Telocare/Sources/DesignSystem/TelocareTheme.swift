import SwiftUI
import UIKit

enum TelocareTheme {
    private static var selectedSkinID: TelocareSkinID = .warmCoral
    private static var selectedTokens: TelocareSkinTokens = TelocareSkinCatalog.tokens(for: .warmCoral)

    static var currentSkinID: TelocareSkinID {
        selectedSkinID
    }

    static func configure(skinID: TelocareSkinID) {
        selectedSkinID = skinID
        selectedTokens = TelocareSkinCatalog.tokens(for: skinID)
    }

    static var coral: Color { color(from: selectedTokens.coralHex) }
    static var coralLight: Color { color(from: selectedTokens.coralLightHex) }
    static var coralDark: Color { color(from: selectedTokens.coralDarkHex) }
    static var peach: Color { color(from: selectedTokens.peachHex) }
    static var warmOrange: Color { color(from: selectedTokens.warmOrangeHex) }

    static var sand: Color { color(from: selectedTokens.sandHex) }
    static var cream: Color { color(from: selectedTokens.creamHex) }
    static var warmGray: Color { color(from: selectedTokens.warmGrayHex) }
    static var charcoal: Color { color(from: selectedTokens.charcoalHex) }

    static var success: Color { color(from: selectedTokens.successHex) }
    static var warning: Color { color(from: selectedTokens.warningHex) }
    static var muted: Color { color(from: selectedTokens.mutedHex) }
    static var robust: Color { color(from: selectedTokens.robustHex) }
    static var moderate: Color { color(from: selectedTokens.moderateHex) }
    static var preliminary: Color { color(from: selectedTokens.preliminaryHex) }
    static var mechanism: Color { color(from: selectedTokens.mechanismHex) }
    static var symptom: Color { color(from: selectedTokens.symptomHex) }
    static var intervention: Color { color(from: selectedTokens.interventionHex) }
    static var graphEdgeCausal: Color { color(from: selectedTokens.graph.edgeCausalColor) }
    static var graphEdgeProtective: Color { color(from: selectedTokens.graph.edgeProtectiveColor) }
    static var graphEdgeFeedback: Color { color(from: selectedTokens.graph.edgeFeedbackColor) }
    static var graphEdgeMechanism: Color { color(from: selectedTokens.graph.edgeMechanismColor) }
    static var graphEdgeIntervention: Color { color(from: selectedTokens.graph.edgeInterventionColor) }

    static var graphSkin: GraphSkin {
        let graph = selectedTokens.graph
        return GraphSkin(
            backgroundColor: graph.backgroundColor,
            textColor: graph.textColor,
            nodeBackgroundColor: graph.nodeBackgroundColor,
            nodeBorderDefaultColor: graph.nodeBorderDefaultColor,
            nodeBorderRobustColor: graph.nodeBorderRobustColor,
            nodeBorderModerateColor: graph.nodeBorderModerateColor,
            nodeBorderPreliminaryColor: graph.nodeBorderPreliminaryColor,
            nodeBorderMechanismColor: graph.nodeBorderMechanismColor,
            nodeBorderSymptomColor: graph.nodeBorderSymptomColor,
            nodeBorderInterventionColor: graph.nodeBorderInterventionColor,
            edgeTextBackgroundColor: graph.edgeTextBackgroundColor,
            tooltipBackgroundColor: graph.tooltipBackgroundColor,
            tooltipBorderColor: graph.tooltipBorderColor,
            selectionOverlayColor: graph.selectionOverlayColor,
            edgeCausalColor: graph.edgeCausalColor,
            edgeProtectiveColor: graph.edgeProtectiveColor,
            edgeFeedbackColor: graph.edgeFeedbackColor,
            edgeMechanismColor: graph.edgeMechanismColor,
            edgeInterventionColor: graph.edgeInterventionColor
        )
    }

    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 13, weight: .regular, design: .rounded)
        static let small = Font.system(size: 11, weight: .medium, design: .rounded)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radii
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Shadows
    static let softShadow = WarmShadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    static let cardShadow = WarmShadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)

    private static func color(from hex: String) -> Color {
        guard let uiColor = UIColor(hex: hex) else {
            return .clear
        }

        return Color(uiColor: uiColor)
    }
}

struct WarmShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

private extension UIColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned

        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
