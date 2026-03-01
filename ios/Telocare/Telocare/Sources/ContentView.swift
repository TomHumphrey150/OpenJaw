import SwiftUI

private enum RootModal: String, Identifiable {
    case globalLens
    case profile

    var id: String { rawValue }
}

struct ContentView: View {
    @Bindable var rootViewModel: RootViewModel

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
                ReadyDashboardRootView(
                    dashboardViewModel: dashboardViewModel,
                    selectedSkinID: rootViewModel.selectedSkinID,
                    isMuseEnabled: rootViewModel.isMuseEnabled,
                    accountDescription: accountDescription,
                    onSelectSkin: rootViewModel.setSkin,
                    onSetMuseEnabled: rootViewModel.setMuseEnabled,
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

private struct ReadyDashboardRootView: View {
    @Bindable var dashboardViewModel: AppViewModel
    let selectedSkinID: TelocareSkinID
    let isMuseEnabled: Bool
    let accountDescription: String
    let onSelectSkin: (TelocareSkinID) -> Void
    let onSetMuseEnabled: (Bool) -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topChrome

            DashboardContentView(
                viewModel: dashboardViewModel,
                selectedSkinID: selectedSkinID,
                isMuseEnabled: isMuseEnabled
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TelocareTheme.sand.ignoresSafeArea(edges: .top))
        .sheet(item: rootModalBinding(for: dashboardViewModel)) { modal in
            switch modal {
            case .globalLens:
                GlobalLensSheet(
                    mode: dashboardViewModel.projectedHealthLensMode,
                    selection: dashboardViewModel.projectedHealthLensSelection,
                    corePillars: dashboardViewModel.projectedCoreHealthLensPillars,
                    userDefinedPillars: dashboardViewModel.projectedUserDefinedHealthLensPillars,
                    userDefinedPillarRows: dashboardViewModel.projectedUserDefinedPillars,
                    onSelectAll: dashboardViewModel.selectAllHealthLensPillars,
                    onSelectNone: dashboardViewModel.clearHealthLensPillars,
                    onTogglePillar: dashboardViewModel.toggleHealthLensPillar,
                    onCreatePillar: { templateID, title in
                        dashboardViewModel.createUserDefinedPillar(templateID: templateID, title: title)
                    },
                    onRenamePillar: { pillarID, title in
                        dashboardViewModel.renameUserDefinedPillar(pillarID: pillarID, title: title)
                    },
                    onSetPillarArchived: { pillarID, isArchived in
                        dashboardViewModel.setUserDefinedPillarArchived(pillarID: pillarID, isArchived: isArchived)
                    },
                    onClose: {
                        dashboardViewModel.setLensControlExpanded(false)
                    }
                )
            case .profile:
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
        }
    }

    private func rootModalBinding(for viewModel: AppViewModel) -> Binding<RootModal?> {
        Binding(
            get: { activeRootModal(for: viewModel) },
            set: { nextModal in
                switch nextModal {
                case .globalLens:
                    viewModel.setProfileSheetPresented(false)
                    viewModel.setLensControlExpanded(true)
                case .profile:
                    viewModel.setLensControlExpanded(false)
                    viewModel.setProfileSheetPresented(true)
                case nil:
                    viewModel.setLensControlExpanded(false)
                    viewModel.setProfileSheetPresented(false)
                }
            }
        )
    }

    private func activeRootModal(for viewModel: AppViewModel) -> RootModal? {
        if viewModel.isProfileSheetPresented {
            return .profile
        }

        if viewModel.projectedLensControlState.isExpanded {
            return .globalLens
        }

        return nil
    }

    @ViewBuilder
    private var topChrome: some View {
        ZStack(alignment: .topTrailing) {
            GlobalLensStatusBar(
                label: dashboardViewModel.projectedHealthLensLabel,
                visiblePillars: dashboardViewModel.projectedVisibleHealthLensPillars,
                onTap: {
                    dashboardViewModel.setLensControlExpanded(true)
                }
            )

            ProfileAvatarButton(mode: dashboardViewModel.mode) {
                dashboardViewModel.openProfileSheet()
            }
        }
        .background(TelocareTheme.sand.opacity(0.97))
    }
}

private struct GlobalLensStatusBar: View {
    let label: String
    let visiblePillars: [HealthPillarDefinition]
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(TelocareTheme.coral)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Lens")
                        .font(.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TelocareTheme.charcoal)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TelocareTheme.warmGray)
            }

            if !visiblePillars.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TelocareTheme.Spacing.sm) {
                        ForEach(visiblePillars) { pillar in
                            GlobalLensPillarBadge(pillar: pillar)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Visible pillars")
                .accessibilityValue(visiblePillars.map(\.title).joined(separator: ", "))
                .accessibilityIdentifier(AccessibilityID.globalLensBadgeStrip)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TelocareTheme.cream)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TelocareTheme.peach, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.horizontal, TelocareTheme.Spacing.md)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(TelocareTheme.sand.opacity(0.97))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Global lens")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens global lens controls.")
        .accessibilityIdentifier(AccessibilityID.globalLensNub)
    }

    private var accessibilityValue: String {
        if visiblePillars.isEmpty {
            return label
        }

        let visiblePillarTitles = visiblePillars.map(\.title).joined(separator: ", ")
        return "\(label). Showing \(visiblePillarTitles)"
    }
}

private struct GlobalLensPillarBadge: View {
    let pillar: HealthPillarDefinition

    var body: some View {
        Text(badgeText)
            .font(TelocareTheme.Typography.small.weight(.bold))
            .foregroundStyle(TelocareTheme.charcoal)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(TelocareTheme.peach)
            )
            .overlay(
                Circle()
                    .stroke(TelocareTheme.coral.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel(pillar.title)
            .accessibilityIdentifier(AccessibilityID.globalLensBadge(pillar: pillar.id.id))
    }

    private var badgeText: String {
        let tokens = pillar.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if tokens.isEmpty {
            return "?"
        }

        if tokens.count == 1 {
            return String(tokens[0].prefix(2)).uppercased()
        }

        let firstLetter = tokens[0].first.map(String.init) ?? ""
        let secondLetter = tokens[1].first.map(String.init) ?? ""
        return (firstLetter + secondLetter).uppercased()
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
                .foregroundStyle(TelocareTheme.charcoal)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(TelocareTheme.warmGray)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TelocareTheme.sand.ignoresSafeArea())
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct FatalScreen: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration Error")
                .font(.title3.bold())
                .foregroundStyle(TelocareTheme.charcoal)
            Text(message)
                .font(.body)
                .foregroundStyle(TelocareTheme.charcoal)
            Text("Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY through Tuist xcconfig files.")
                .font(.footnote)
                .foregroundStyle(TelocareTheme.warmGray)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TelocareTheme.sand.ignoresSafeArea())
    }
}
