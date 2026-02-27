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
        ZStack(alignment: .topTrailing) {
            ExploreTabShell(
                viewModel: viewModel,
                selectedSkinID: selectedSkinID,
                isMuseSessionEnabled: isMuseEnabled
            )
            ProfileAvatarButton(mode: viewModel.mode, action: viewModel.openProfileSheet)
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
}
