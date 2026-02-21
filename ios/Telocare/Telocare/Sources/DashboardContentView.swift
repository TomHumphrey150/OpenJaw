import SwiftUI

struct DashboardContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    let accountDescription: String
    let onSignOut: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            currentModeView
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
        .animation(.easeInOut(duration: 0.28), value: viewModel.guidedStep)
        .animation(.easeInOut(duration: 0.28), value: viewModel.mode)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.handleAppMovedToBackground()
            }
        }
    }

    @ViewBuilder
    private var currentModeView: some View {
        switch viewModel.mode {
        case .guided:
            GuidedFlowPager(viewModel: viewModel)
        case .explore:
            ExploreTabShell(viewModel: viewModel)
        }
    }
}
