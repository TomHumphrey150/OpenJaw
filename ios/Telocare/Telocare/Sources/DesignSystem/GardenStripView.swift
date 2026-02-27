import SwiftUI

struct GardenStripView: View {
    let gardens: [GardenSnapshot]
    @Binding var selectedPathway: GardenPathway?

    var body: some View {
        HStack(spacing: TelocareTheme.Spacing.sm) {
            ForEach(gardens) { garden in
                GardenCard(
                    garden: garden,
                    isSelected: selectedPathway == garden.pathway,
                    onTap: { toggleSelection(garden.pathway) }
                )
            }
        }
    }

    private func toggleSelection(_ pathway: GardenPathway) {
        withAnimation(.spring(response: 0.3)) {
            if selectedPathway == pathway {
                selectedPathway = nil
            } else {
                selectedPathway = pathway
            }
        }
    }
}

private struct GardenCard: View {
    let garden: GardenSnapshot
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: TelocareTheme.Spacing.xs) {
                GardenPlotView(
                    pathway: garden.pathway,
                    bloomLevel: garden.bloomLevel
                )

                Text(garden.pathway.displayName)
                    .font(TelocareTheme.Typography.headline)
                    .foregroundStyle(isSelected ? TelocareTheme.coral : TelocareTheme.charcoal)

                Text(garden.summaryText)
                    .font(TelocareTheme.Typography.small)
                    .foregroundStyle(TelocareTheme.warmGray)
            }
            .padding(TelocareTheme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(TelocareTheme.cream)
            .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous)
                    .stroke(isSelected ? TelocareTheme.coral : .clear, lineWidth: 2)
            )
            .shadow(
                color: TelocareTheme.cardShadow.color,
                radius: TelocareTheme.cardShadow.radius,
                x: TelocareTheme.cardShadow.x,
                y: TelocareTheme.cardShadow.y
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(garden.pathway.displayName) garden")
        .accessibilityValue("\(garden.summaryText), bloom level \(Int(garden.bloomLevel * 100))%")
        .accessibilityHint(isSelected ? "Tap to show all habits" : "Tap to filter to \(garden.pathway.displayName) habits")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
