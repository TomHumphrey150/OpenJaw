import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Telocare")
                    .font(.largeTitle.bold())
                Text("Sign in with email and password")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("you@example.com", text: $viewModel.authEmail)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isAuthBusy)
                    .accessibilityIdentifier(AccessibilityID.authEmailInput)

                SecureField("Password", text: $viewModel.authPassword)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isAuthBusy)
                    .accessibilityIdentifier(AccessibilityID.authPasswordInput)
            }

            HStack(spacing: 10) {
                Button("Sign In") {
                    viewModel.submitSignIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAuthBusy)
                .accessibilityIdentifier(AccessibilityID.authSignInButton)

                Button("Create Account") {
                    viewModel.submitSignUp()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isAuthBusy)
                .accessibilityIdentifier(AccessibilityID.authCreateAccountButton)
            }

            if viewModel.isAuthBusy {
                ProgressView()
            }

            if let error = viewModel.authErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.authErrorMessage)
            }

            if let status = viewModel.authStatusMessage {
                Text(status)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.authStatusMessage)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}
