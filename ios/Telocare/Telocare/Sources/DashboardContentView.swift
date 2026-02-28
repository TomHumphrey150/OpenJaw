import SwiftUI

struct DashboardContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    let selectedSkinID: TelocareSkinID
    let isMuseEnabled: Bool
    let onSelectSkin: (TelocareSkinID) -> Void
    let onSetMuseEnabled: (Bool) -> Void
    let accountDescription: String
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            ExploreTabShell(
                viewModel: viewModel,
                selectedSkinID: selectedSkinID,
                isMuseSessionEnabled: isMuseEnabled
            )

            if shouldShowGlobalLensControl {
                GlobalLensFloatingControl(
                    preset: viewModel.projectedHealthLensPreset,
                    pillars: viewModel.projectedHealthLensPillars,
                    selectedPillar: viewModel.projectedHealthLensPillar,
                    controlState: viewModel.projectedLensControlState,
                    onSetPreset: viewModel.setHealthLensPreset,
                    onSetPillar: viewModel.setHealthLensPillar,
                    onSetPosition: viewModel.setLensControlPosition,
                    onSetExpanded: viewModel.setLensControlExpanded,
                    onMoveToCorner: viewModel.moveLensControl,
                    onResetPosition: viewModel.resetLensControlPosition
                )
            }

            VStack {
                HStack {
                    Spacer()
                    ProfileAvatarButton(mode: viewModel.mode, action: viewModel.openProfileSheet)
                }
                Spacer()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isProfileSheetPresented },
                set: viewModel.setProfileSheetPresented
            )
        ) {
            ProfileSheetView(
                accountDescription: accountDescription,
                selectedSkinID: selectedSkinID,
                isMuseEnabled: isMuseEnabled,
                onSelectSkin: onSelectSkin,
                onSetMuseEnabled: onSetMuseEnabled,
                onSignOut: onSignOut
            )
            .accessibilityIdentifier(AccessibilityID.profileSheet)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.handleAppMovedToBackground()
                return
            }

            if newPhase == .active {
                Task {
                    await viewModel.refreshAllConnectedAppleHealth(trigger: .automatic)
                }
            }
        }
    }

    private var shouldShowGlobalLensControl: Bool {
        guard viewModel.mode == .explore else {
            return false
        }
        switch viewModel.selectedExploreTab {
        case .inputs, .outcomes, .situation:
            return true
        case .chat:
            return false
        }
    }
}

enum GlobalLensNubBadge {
    static func text(for preset: HealthLensPreset, selectedPillar: HealthPillar?) -> String {
        switch preset {
        case .all:
            return "All"
        case .foundation:
            return "Fdn"
        case .acute:
            return "Aqt"
        case .pillar:
            guard let selectedPillar else {
                return "Plr"
            }
            return pillarCode(for: selectedPillar.displayName)
        }
    }

    private static func pillarCode(for title: String) -> String {
        let words = title.split { character in
            character.isWhitespace || character == "/" || character == "-"
        }

        if words.count > 1 {
            let acronym = words
                .prefix(3)
                .compactMap(\.first)
                .map { String($0).uppercased() }
                .joined()
            if !acronym.isEmpty {
                return acronym
            }
        }

        let merged = words.joined()
        guard !merged.isEmpty else {
            return "Plr"
        }
        return String(merged.prefix(3)).uppercased()
    }
}

func globalLensAccessibilityIdentifier(for preset: HealthLensPreset) -> String {
    switch preset {
    case .all:
        return AccessibilityID.exploreInputsLensAll
    case .foundation:
        return AccessibilityID.exploreInputsLensFoundation
    case .acute:
        return AccessibilityID.exploreInputsLensAcute
    case .pillar:
        return AccessibilityID.exploreInputsLensPillar
    }
}

private struct GlobalLensFloatingControl: View {
    let preset: HealthLensPreset
    let pillars: [HealthPillarDefinition]
    let selectedPillar: HealthPillar?
    let controlState: LensControlState
    let onSetPreset: (HealthLensPreset) -> Void
    let onSetPillar: (HealthPillar) -> Void
    let onSetPosition: (LensControlPosition) -> Void
    let onSetExpanded: (Bool) -> Void
    let onMoveToCorner: (LensControlCorner) -> Void
    let onResetPosition: () -> Void
    @State private var draggedPosition: LensControlPosition?
    @State private var dragStartPosition: LensControlPosition?

    var body: some View {
        GeometryReader { geometry in
            let nubSize: CGFloat = 56
            let resolvedPosition = draggedPosition ?? controlState.position
            let centerPoint = clampedCenterPoint(
                for: resolvedPosition,
                in: geometry.size,
                nubSize: nubSize
            )

            LensNub(badgeText: GlobalLensNubBadge.text(for: preset, selectedPillar: selectedPillar))
                .frame(width: nubSize, height: nubSize)
                .position(x: centerPoint.x, y: centerPoint.y)
                .highPriorityGesture(
                    dragGesture(
                        in: geometry.size,
                        nubSize: nubSize
                    )
                )
                .onTapGesture {
                    onSetExpanded(true)
                }
                .sheet(
                isPresented: Binding(
                    get: { controlState.isExpanded },
                    set: onSetExpanded
                )
            ) {
                GlobalLensSheet(
                    preset: preset,
                    pillars: pillars,
                    selectedPillar: selectedPillar,
                    onSetPreset: onSetPreset,
                    onSetPillar: onSetPillar,
                    onMoveToCorner: onMoveToCorner,
                    onResetPosition: onResetPosition,
                    onClose: { onSetExpanded(false) }
                )
            }
            .accessibilityLabel("Global lens")
            .accessibilityValue(GlobalLensNubBadge.text(for: preset, selectedPillar: selectedPillar))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(AccessibilityID.globalLensNub)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private func dragGesture(in size: CGSize, nubSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let anchor = dragStartPosition ?? draggedPosition ?? controlState.position
                if dragStartPosition == nil {
                    dragStartPosition = anchor
                }

                let width = max(1, size.width)
                let height = max(1, size.height)
                let anchorPoint = clampedCenterPoint(for: anchor, in: size, nubSize: nubSize)
                let nextPoint = CGPoint(
                    x: anchorPoint.x + value.translation.width,
                    y: anchorPoint.y + value.translation.height
                )
                let clampedPoint = clampedPointWithinBounds(nextPoint, in: size, nubSize: nubSize)
                draggedPosition = LensControlPosition(
                    horizontalRatio: Double(clampedPoint.x / width),
                    verticalRatio: Double(clampedPoint.y / height)
                )
            }
            .onEnded { _ in
                if let draggedPosition {
                    onSetPosition(draggedPosition)
                }
                dragStartPosition = nil
                draggedPosition = nil
            }
    }

    private func clampedCenterPoint(
        for position: LensControlPosition,
        in size: CGSize,
        nubSize: CGFloat
    ) -> CGPoint {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let rawPoint = CGPoint(
            x: CGFloat(position.horizontalRatio) * width,
            y: CGFloat(position.verticalRatio) * height
        )
        return clampedPointWithinBounds(rawPoint, in: size, nubSize: nubSize)
    }

    private func clampedPointWithinBounds(_ point: CGPoint, in size: CGSize, nubSize: CGFloat) -> CGPoint {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let minimumX = min(nubSize / 2, width / 2)
        let maximumX = max(minimumX, width - (nubSize / 2))
        let minimumY = min(nubSize / 2, height / 2)
        let maximumY = max(minimumY, height - (nubSize / 2))

        return CGPoint(
            x: min(maximumX, max(minimumX, point.x)),
            y: min(maximumY, max(minimumY, point.y))
        )
    }

}

private struct LensNub: View {
    let badgeText: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(TelocareTheme.coral)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(TelocareTheme.cream)
                )
                .overlay(
                    Circle()
                        .stroke(TelocareTheme.peach, lineWidth: 1)
                )

            Text(badgeText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(TelocareTheme.coral)
                .clipShape(Capsule())
                .offset(x: 6, y: -6)
        }
    }
}

private struct GlobalLensSheet: View {
    let preset: HealthLensPreset
    let pillars: [HealthPillarDefinition]
    let selectedPillar: HealthPillar?
    let onSetPreset: (HealthLensPreset) -> Void
    let onSetPillar: (HealthPillar) -> Void
    let onMoveToCorner: (LensControlCorner) -> Void
    let onResetPosition: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                    Text("Lens")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)

                    ForEach(HealthLensPreset.allCases, id: \.self) { lensPreset in
                        Button {
                            onSetPreset(lensPreset)
                        } label: {
                            HStack {
                                Text(lensPreset.displayName)
                                    .font(TelocareTheme.Typography.body)
                                    .foregroundStyle(TelocareTheme.charcoal)
                                Spacer()
                                if lensPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(TelocareTheme.success)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(globalLensAccessibilityIdentifier(for: lensPreset))
                    }

                    if preset == .pillar {
                        Divider()
                            .background(TelocareTheme.peach)
                        ForEach(pillars) { pillar in
                            Button {
                                onSetPillar(pillar.id)
                            } label: {
                                HStack {
                                    Text(pillar.title)
                                        .font(TelocareTheme.Typography.body)
                                        .foregroundStyle(TelocareTheme.charcoal)
                                    Spacer()
                                    if selectedPillar == pillar.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(TelocareTheme.success)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityID.exploreInputsLensPillar(pillar: pillar.id.rawValue))
                        }
                    }

                    Divider()
                        .background(TelocareTheme.peach)

                    Text("Position")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)

                    ForEach(LensControlCorner.allCases, id: \.self) { corner in
                        Button {
                            onMoveToCorner(corner)
                        } label: {
                            Text(cornerTitle(corner))
                                .font(TelocareTheme.Typography.body)
                                .foregroundStyle(TelocareTheme.charcoal)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onResetPosition()
                    } label: {
                        Text("Reset position")
                            .font(TelocareTheme.Typography.body)
                            .foregroundStyle(TelocareTheme.coral)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.globalLensResetPosition)
                }
                .padding(TelocareTheme.Spacing.md)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Global Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.globalLensSheet)
    }

    private func cornerTitle(_ corner: LensControlCorner) -> String {
        switch corner {
        case .lowerRight:
            return "Move to lower right"
        case .lowerLeft:
            return "Move to lower left"
        case .upperRight:
            return "Move to upper right"
        case .upperLeft:
            return "Move to upper left"
        }
    }
}
