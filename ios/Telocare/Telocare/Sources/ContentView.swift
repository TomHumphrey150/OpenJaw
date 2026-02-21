import SwiftUI

struct ContentView: View {
    @ObservedObject var rootViewModel: RootViewModel

    var body: some View {
        switch rootViewModel.state {
        case .booting:
            ProgressScreen(
                title: "Starting Telocare",
                subtitle: "Checking authentication state.",
                accessibilityID: AccessibilityID.rootBooting
            )
        case .auth:
            AuthView(viewModel: rootViewModel)
        case .hydrating:
            ProgressScreen(
                title: "Loading Dashboard",
                subtitle: "Fetching your data from Supabase.",
                accessibilityID: AccessibilityID.rootHydrating
            )
        case .ready:
            if let dashboardViewModel = rootViewModel.dashboardViewModel {
                DashboardContentView(
                    viewModel: dashboardViewModel,
                    accountDescription: accountDescription,
                    onSignOut: rootViewModel.signOut
                )
            } else {
                ProgressScreen(
                    title: "Preparing Dashboard",
                    subtitle: "Finishing setup.",
                    accessibilityID: AccessibilityID.rootHydrating
                )
            }
        case .fatal(let message):
            FatalScreen(message: message)
                .accessibilityIdentifier(AccessibilityID.rootFatal)
        }
    }

    private var accountDescription: String {
        if let email = rootViewModel.currentUserEmail {
            return "Signed in as \(email)."
        }

        return "Signed in as the active Telecare user profile."
    }
}

private struct ProgressScreen: View {
    let title: String
    let subtitle: String
    let accessibilityID: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct FatalScreen: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration Error")
                .font(.title3.bold())
            Text(message)
                .font(.body)
            Text("Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY through Tuist xcconfig files.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
