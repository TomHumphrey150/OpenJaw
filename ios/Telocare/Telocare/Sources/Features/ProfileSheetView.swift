import SwiftUI

struct ProfileSheetView: View {
    let accountDescription: String
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink(
                    destination: ProfileEntryDetailView(
                        title: "Account",
                        message: accountDescription
                    )
                ) {
                    Label("Account", systemImage: "person.text.rectangle")
                }
                .accessibilityIdentifier(AccessibilityID.profileAccountEntry)

                NavigationLink(
                    destination: ProfileEntryDetailView(
                        title: "Settings",
                        message: "Settings include text-first and accessibility preferences."
                    )
                ) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier(AccessibilityID.profileSettingsEntry)

                Button {
                    onSignOut()
                    dismiss()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier(AccessibilityID.profileSignOutEntry)
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.body)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
