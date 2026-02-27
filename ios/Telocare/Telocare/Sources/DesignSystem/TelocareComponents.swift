import SwiftUI

// MARK: - Warm Card Component

struct WarmCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = TelocareTheme.Spacing.md

    init(padding: CGFloat = TelocareTheme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(TelocareTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous))
            .shadow(
                color: TelocareTheme.cardShadow.color,
                radius: TelocareTheme.cardShadow.radius,
                x: TelocareTheme.cardShadow.x,
                y: TelocareTheme.cardShadow.y
            )
    }
}

// MARK: - Primary Button Style

struct WarmPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TelocareTheme.Typography.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, TelocareTheme.Spacing.lg)
            .padding(.vertical, TelocareTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.pill, style: .continuous)
                    .fill(configuration.isPressed ? TelocareTheme.coralDark : TelocareTheme.coral)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct WarmSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TelocareTheme.Typography.headline)
            .foregroundStyle(TelocareTheme.coral)
            .padding(.horizontal, TelocareTheme.Spacing.lg)
            .padding(.vertical, TelocareTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.pill, style: .continuous)
                    .fill(TelocareTheme.peach)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Section Header

struct WarmSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
            Text(title)
                .font(TelocareTheme.Typography.headline)
                .foregroundStyle(TelocareTheme.charcoal)
            if let subtitle {
                Text(subtitle)
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
            }
        }
    }
}

// MARK: - Progress Ring

struct WarmProgressRing: View {
    let progress: Double
    var size: CGFloat = 48
    var lineWidth: CGFloat = 6
    var badgeSystemImage: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(TelocareTheme.peach, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    TelocareTheme.coral,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(TelocareTheme.Typography.small)
                .foregroundStyle(TelocareTheme.charcoal)

            if let badgeSystemImage {
                Image(systemName: badgeSystemImage)
                    .font(TelocareTheme.Typography.small)
                    .foregroundStyle(TelocareTheme.warmOrange)
                    .padding(5)
                    .background(TelocareTheme.cream)
                    .clipShape(Circle())
                    .offset(x: size * 0.26, y: -size * 0.26)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Chip/Pill Badge

struct WarmChip: View {
    let text: String
    var isSelected: Bool = false

    var body: some View {
        Text(text)
            .font(TelocareTheme.Typography.small)
            .foregroundStyle(isSelected ? .white : TelocareTheme.coral)
            .padding(.horizontal, TelocareTheme.Spacing.sm)
            .padding(.vertical, TelocareTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? TelocareTheme.coral : TelocareTheme.peach)
            )
    }
}

// MARK: - Empty State View

struct WarmEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: TelocareTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(TelocareTheme.muted)
            Text(title)
                .font(TelocareTheme.Typography.headline)
                .foregroundStyle(TelocareTheme.charcoal)
            Text(message)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.warmGray)
                .multilineTextAlignment(.center)
        }
        .padding(TelocareTheme.Spacing.xl)
    }
}
