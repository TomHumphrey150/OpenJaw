import Foundation

struct AppConfiguration {
    let supabaseURL: URL
    let supabasePublishableKey: String

    init(bundle: Bundle = .main) throws {
        let rawURL = try AppConfiguration.requiredValue(for: "SUPABASE_URL", bundle: bundle)
        let rawKey = try AppConfiguration.requiredValue(for: "SUPABASE_PUBLISHABLE_KEY", bundle: bundle)
        try self.init(
            supabaseURLString: rawURL,
            supabasePublishableKey: rawKey
        )
    }

    init(supabaseURLString: String, supabasePublishableKey: String) throws {
        let rawURL = try AppConfiguration.validatedValue(supabaseURLString, key: "SUPABASE_URL")
        let rawKey = try AppConfiguration.validatedValue(supabasePublishableKey, key: "SUPABASE_PUBLISHABLE_KEY")

        guard let url = URL(string: rawURL), url.scheme != nil, url.host != nil else {
            throw AppConfigurationError.invalidValue(key: "SUPABASE_URL")
        }

        supabaseURL = url
        self.supabasePublishableKey = rawKey
    }

    private static func requiredValue(for key: String, bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            throw AppConfigurationError.missingValue(key: key)
        }

        return try validatedValue(value, key: key)
    }

    private static func validatedValue(_ value: String, key: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppConfigurationError.missingValue(key: key)
        }

        let uppercased = trimmed.uppercased()
        if uppercased.contains("YOUR_SUPABASE") || uppercased.contains("REPLACE_ME") {
            throw AppConfigurationError.placeholderValue(key: key)
        }

        return trimmed
    }
}

enum AppConfigurationError: Error {
    case missingValue(key: String)
    case invalidValue(key: String)
    case placeholderValue(key: String)
}

extension AppConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingValue(let key):
            return "Missing \(key) in app configuration."
        case .invalidValue(let key):
            return "Invalid \(key) in app configuration."
        case .placeholderValue(let key):
            return "\(key) still uses a placeholder value."
        }
    }
}
