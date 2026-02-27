import SwiftUI

struct GardenBreadcrumbSegment: Equatable, Identifiable {
    let depth: Int
    let title: String

    var id: Int {
        depth
    }
}

struct GardenBreadcrumbView: View {
    let segments: [GardenBreadcrumbSegment]
    let canGoBack: Bool
    let onGoBack: () -> Void
    let onSelectDepth: (Int) -> Void

    var body: some View {
        HStack(spacing: TelocareTheme.Spacing.xs) {
            if canGoBack {
                Button(action: onGoBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TelocareTheme.charcoal)
                        .frame(width: 44, height: 44)
                        .background(TelocareTheme.cream)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(AccessibilityID.exploreInputsGardenBreadcrumbBack)
                .accessibilityLabel("Back one garden level")
                .accessibilityHint("Moves to the previous garden level.")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TelocareTheme.Spacing.xs) {
                    ForEach(segments) { segment in
                        chip(for: segment)

                        if segment.depth != segments.last?.depth {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(TelocareTheme.muted)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.exploreInputsGardenBreadcrumb)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(for segment: GardenBreadcrumbSegment) -> some View {
        Button {
            onSelectDepth(segment.depth)
        } label: {
            Text(segment.title)
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.charcoal)
                .padding(.horizontal, TelocareTheme.Spacing.sm)
                .frame(minHeight: 44)
                .background(TelocareTheme.cream)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            AccessibilityID.exploreInputsGardenBreadcrumbChip(depth: segment.depth)
        )
        .accessibilityLabel(segment.title)
        .accessibilityHint("Navigates to this garden level.")
    }
}
