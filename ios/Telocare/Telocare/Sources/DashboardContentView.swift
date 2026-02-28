import SwiftUI

struct DashboardContentView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    let selectedSkinID: TelocareSkinID
    let isMuseEnabled: Bool

    var body: some View {
        ZStack {
            ExploreTabShell(
                viewModel: viewModel,
                selectedSkinID: selectedSkinID,
                isMuseSessionEnabled: isMuseEnabled
            )

            VStack {
                HStack {
                    Spacer()
                    ProfileAvatarButton(mode: viewModel.mode) {
                        viewModel.openProfileSheet()
                    }
                }
                Spacer()
            }
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

struct GlobalLensSheet: View {
    let preset: HealthLensPreset
    let pillars: [HealthPillarDefinition]
    let selectedPillar: HealthPillar?
    let onSetPreset: (HealthLensPreset) -> Void
    let onSetPillar: (HealthPillar) -> Void
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
                }
                .padding(TelocareTheme.Spacing.md)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Global Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onClose()
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.globalLensSheet)
    }
}
