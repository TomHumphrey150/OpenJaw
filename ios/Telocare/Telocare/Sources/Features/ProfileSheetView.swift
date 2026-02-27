import SwiftUI

struct ProfileSheetView: View {
    let accountDescription: String
    let selectedSkinID: TelocareSkinID
    let isMuseEnabled: Bool
    let onSelectSkin: (TelocareSkinID) -> Void
    let onSetMuseEnabled: (Bool) -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(
                        destination: ProfileEntryDetailView(
                            title: "Account",
                            message: accountDescription
                        )
                    ) {
                        Label("Account", systemImage: "person.text.rectangle")
                            .foregroundStyle(TelocareTheme.charcoal)
                    }
                    .accessibilityIdentifier(AccessibilityID.profileAccountEntry)
                } header: {
                    Text("General")
                        .font(TelocareTheme.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }

                Section {
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Text("Appearance")
                            .font(TelocareTheme.Typography.headline)
                            .foregroundStyle(TelocareTheme.charcoal)
                        Text("Applies immediately across the app.")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                    }
                    .padding(.vertical, TelocareTheme.Spacing.xs)
                    .accessibilityIdentifier(AccessibilityID.profileThemeSection)

                    ThemeOptionRow(
                        title: TelocareSkinID.warmCoral.displayName,
                        systemImage: "sun.max.fill",
                        isSelected: selectedSkinID == .warmCoral,
                        action: { onSelectSkin(.warmCoral) }
                    )
                    .accessibilityIdentifier(AccessibilityID.profileThemeWarmCoralOption)

                    ThemeOptionRow(
                        title: TelocareSkinID.garden.displayName,
                        systemImage: "leaf.fill",
                        isSelected: selectedSkinID == .garden,
                        action: { onSelectSkin(.garden) }
                    )
                    .accessibilityIdentifier(AccessibilityID.profileThemeGardenOption)

                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Toggle(
                            "Enable Muse recording controls",
                            isOn: Binding(
                                get: { isMuseEnabled },
                                set: onSetMuseEnabled
                            )
                        )
                        .tint(TelocareTheme.coral)
                        .accessibilityIdentifier(AccessibilityID.profileMuseFeatureToggle)

                        Text("Off by default. Turn on only if you want Muse setup and recording controls in Outcomes.")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, TelocareTheme.Spacing.xs)
                } header: {
                    Text("Settings")
                        .font(TelocareTheme.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }

                Section {
                    Button {
                        onSignOut()
                        dismiss()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AccessibilityID.profileSignOutEntry)
                } header: {
                    Text("Account Actions")
                        .font(TelocareTheme.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(TelocareTheme.coral)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(TelocareTheme.sand)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                        .foregroundStyle(TelocareTheme.coral)
                        .accessibilityIdentifier(AccessibilityID.profileCloseButton)
                }
            }
        }
    }
}

private struct ThemeOptionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(TelocareTheme.coral)
                Text(title)
                    .foregroundStyle(TelocareTheme.charcoal)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(TelocareTheme.coral)
                        .font(TelocareTheme.Typography.body.weight(.semibold))
                }
            }
        }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ProfileEntryDetailView: View {
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                WarmCard {
                    Text(message)
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.charcoal)
                }
            }
            .padding(TelocareTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TelocareTheme.sand)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
