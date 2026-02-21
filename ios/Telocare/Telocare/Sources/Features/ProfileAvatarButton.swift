import SwiftUI

struct ProfileAvatarButton: View {
    let mode: AppMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.teal))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 16)
        .accessibilityIdentifier(AccessibilityID.profileButton)
        .accessibilityLabel("Open profile and settings")
        .accessibilityValue(mode == .guided ? "Guided mode" : "Explore mode")
    }
}
