import SwiftUI

struct DashboardContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    let accountDescription: String
    let onSignOut: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ExploreTabShell(viewModel: viewModel)
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
                onSignOut: onSignOut
            )
            .accessibilityIdentifier(AccessibilityID.profileSheet)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.handleAppMovedToBackground()
            }
        }
    }
}
