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

    var body: some View {
        GeometryReader { geometry in
            let nubSize: CGFloat = 56
            let resolvedPosition = draggedPosition ?? controlState.position
            let xPosition = max(
                nubSize / 2,
                min(
                    geometry.size.width - (nubSize / 2),
                    CGFloat(resolvedPosition.horizontalRatio) * geometry.size.width
                )
            )
            let yPosition = max(
                nubSize / 2,
                min(
                    geometry.size.height - (nubSize / 2),
                    CGFloat(resolvedPosition.verticalRatio) * geometry.size.height
                )
            )

            Button {
                onSetExpanded(true)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(TelocareTheme.coral)
                    .frame(width: nubSize, height: nubSize)
                    .background(
                        Circle()
                            .fill(TelocareTheme.cream)
                    )
                    .overlay(
                        Circle()
                            .stroke(TelocareTheme.peach, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .position(x: xPosition, y: yPosition)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(1, geometry.size.width)
                        let height = max(1, geometry.size.height)
                        let nextX = min(max(0, value.location.x / width), 1)
                        let nextY = min(max(0, value.location.y / height), 1)
                        draggedPosition =
                            LensControlPosition(
                                horizontalRatio: nextX,
                                verticalRatio: nextY
                            )
                    }
                    .onEnded { _ in
                        if let draggedPosition {
                            onSetPosition(draggedPosition)
                        }
                        draggedPosition = nil
                    }
            )
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
            .accessibilityIdentifier(AccessibilityID.globalLensNub)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
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
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(lensAccessibilityID(for: lensPreset))
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
                                .frame(minHeight: 44)
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

    private func lensAccessibilityID(for preset: HealthLensPreset) -> String {
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
