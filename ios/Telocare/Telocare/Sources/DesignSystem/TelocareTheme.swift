import SwiftUI

enum TelocareTheme {
    // MARK: - Primary Colors (Warm Coral/Orange Palette)
    static let coral = Color(red: 1.0, green: 0.44, blue: 0.37)
    static let coralLight = Color(red: 1.0, green: 0.55, blue: 0.49)
    static let coralDark = Color(red: 0.89, green: 0.35, blue: 0.29)
    static let peach = Color(red: 1.0, green: 0.87, blue: 0.81)
    static let warmOrange = Color(red: 1.0, green: 0.60, blue: 0.40)

    // MARK: - Neutral Colors
    static let sand = Color(red: 0.98, green: 0.96, blue: 0.93)
    static let cream = Color(red: 1.0, green: 0.99, blue: 0.97)
    static let warmGray = Color(red: 0.55, green: 0.52, blue: 0.50)
    static let charcoal = Color(red: 0.25, green: 0.23, blue: 0.22)

    // MARK: - Semantic Colors
    static let success = Color(red: 0.52, green: 0.76, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.36)
    static let muted = Color(red: 0.75, green: 0.72, blue: 0.70)

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
}

struct WarmShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}
