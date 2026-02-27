import SwiftUI

struct CurrentGardenCardView: View {
    let cluster: GardenClusterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            HStack {
                Spacer(minLength: 0)
                GardenPlotView(
                    themeKey: cluster.themeKey,
                    bloomLevel: cluster.bloomLevel
                )
                Spacer(minLength: 0)
            }

            Text(cluster.title)
                .font(TelocareTheme.Typography.headline)
                .foregroundStyle(TelocareTheme.charcoal)
                .lineLimit(2)

            Text(cluster.summaryText)
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
                .lineLimit(1)

            ProgressView(value: cluster.bloomLevel)
                .tint(TelocareTheme.coral)
        }
        .padding(TelocareTheme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(TelocareTheme.cream)
        .clipShape(
            RoundedRectangle(
                cornerRadius: TelocareTheme.CornerRadius.large,
                style: .continuous
            )
        )
        .shadow(
            color: TelocareTheme.cardShadow.color,
            radius: TelocareTheme.cardShadow.radius,
            x: TelocareTheme.cardShadow.x,
            y: TelocareTheme.cardShadow.y
        )
        .accessibilityIdentifier(
            AccessibilityID.exploreInputsGardenSubgardenCard(nodeID: cluster.nodeID)
        )
        .accessibilityLabel("\(cluster.title) garden")
        .accessibilityValue("\(cluster.summaryText), bloom level \(Int(cluster.bloomLevel * 100))%")
    }
}
