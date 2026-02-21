import SwiftUI

struct ProfileSheetView: View {
    let accountDescription: String
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

                    NavigationLink(
                        destination: ProfileEntryDetailView(
                            title: "Settings",
                            message: "Settings include text-first and accessibility preferences."
                        )
                    ) {
                        Label("Settings", systemImage: "gearshape")
                            .foregroundStyle(TelocareTheme.charcoal)
                    }
                    .accessibilityIdentifier(AccessibilityID.profileSettingsEntry)
                } header: {
                    Text("General")
                        .font(.subheadline)
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
                        .font(.subheadline)
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

private struct ProfileEntryDetailView: View {
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                WarmCard {
                    Text(message)
                        .font(.body)
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
