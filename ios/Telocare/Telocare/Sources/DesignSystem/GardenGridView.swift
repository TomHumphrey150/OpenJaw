import SwiftUI

struct GardenGridView: View {
    let clusters: [GardenClusterSnapshot]
    let selectedNodeID: String?
    let onSelectNode: (String) -> Void

    private let layout = GardenGridLayout()

    private var clusterRows: [[GardenClusterSnapshot]] {
        layout.rows(from: clusters)
    }

    var body: some View {
        VStack(spacing: TelocareTheme.Spacing.sm) {
            ForEach(Array(clusterRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: TelocareTheme.Spacing.sm) {
                    ForEach(row) { cluster in
                        button(for: cluster)
                    }
                    if row.count == 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.exploreInputsGardenSubgardenStrip)
    }

    private func button(for cluster: GardenClusterSnapshot) -> some View {
        Button {
            onSelectNode(cluster.nodeID)
        } label: {
            GardenCardContent(cluster: cluster, isSelected: selectedNodeID == cluster.nodeID)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            AccessibilityID.exploreInputsGardenSubgardenCard(nodeID: cluster.nodeID)
        )
        .accessibilityLabel("\(cluster.title) garden")
        .accessibilityValue("\(cluster.summaryText), bloom level \(Int(cluster.bloomLevel * 100))%")
        .accessibilityHint("Filters habits to this garden branch.")
        .accessibilityAddTraits(selectedNodeID == cluster.nodeID ? .isSelected : [])
    }
}

private struct GardenCardContent: View {
    let cluster: GardenClusterSnapshot
    let isSelected: Bool

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
        .overlay(
            RoundedRectangle(
                cornerRadius: TelocareTheme.CornerRadius.large,
                style: .continuous
            )
            .stroke(
                isSelected ? TelocareTheme.coral : .clear,
                lineWidth: 2
            )
        )
        .shadow(
            color: TelocareTheme.cardShadow.color,
            radius: TelocareTheme.cardShadow.radius,
            x: TelocareTheme.cardShadow.x,
            y: TelocareTheme.cardShadow.y
        )
    }
}
