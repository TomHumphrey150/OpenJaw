import Foundation

struct AuthErrorMessageMapper {
    static func message(for error: Error, operation: AuthOperation) -> String {
        if let inputError = error as? AuthInputError, inputError == .missingCredentials {
            return "Enter both email and password."
        }

        let message = String(describing: error).lowercased()

        if message.contains("invalid login credentials") {
            return "Invalid email/password, or account does not exist yet. Tap Create Account first."
        }

        if message.contains("email not confirmed") {
            return "Email is not confirmed. Check your inbox, or disable Confirm email in Supabase Authentication settings."
        }

        if message.contains("email logins are disabled") {
            return "Email/password login is disabled in Supabase. Enable it under Authentication > Providers > Email."
        }

        if operation == .signUp && (message.contains("signup") || message.contains("sign up")) {
            return "Account creation is disabled in Supabase. Enable email signups under Authentication > Providers > Email."
        }

        if let localized = (error as NSError).localizedDescription.nilIfEmpty {
            return localized
        }

        return "Authentication failed."
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
