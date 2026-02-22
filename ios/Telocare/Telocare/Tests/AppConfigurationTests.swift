import Foundation
import Testing
@testable import Telocare

struct AppConfigurationTests {
    @Test func acceptsValidConfigValues() throws {
        let configuration = try AppConfiguration(
            supabaseURLString: "https://aocndwnnkffumisprifx.supabase.co",
            supabasePublishableKey: "sb_publishable_test"
        )

        #expect(configuration.supabasePublishableKey == "sb_publishable_test")
        #expect(configuration.supabaseURL.absoluteString == "https://aocndwnnkffumisprifx.supabase.co")
        #expect(configuration.museLicenseData == nil)
    }

    @Test func rejectsPlaceholderConfigValues() {
        #expect(throws: AppConfigurationError.self) {
            try AppConfiguration(
                supabaseURLString: "YOUR_SUPABASE_URL",
                supabasePublishableKey: "sb_publishable_test"
            )
        }
    }

    @Test func decodesOptionalMuseLicenseWhenBase64IsValid() throws {
        let rawLicense = Data("muse-license".utf8).base64EncodedString()
        let configuration = try AppConfiguration(
            supabaseURLString: "https://aocndwnnkffumisprifx.supabase.co",
            supabasePublishableKey: "sb_publishable_test",
            museLicenseBase64: rawLicense
        )

        #expect(configuration.museLicenseData == Data("muse-license".utf8))
    }

    @Test func ignoresOptionalMuseLicenseWhenBase64IsInvalid() throws {
        let configuration = try AppConfiguration(
            supabaseURLString: "https://aocndwnnkffumisprifx.supabase.co",
            supabasePublishableKey: "sb_publishable_test",
            museLicenseBase64: "not base64"
        )

        #expect(configuration.museLicenseData == nil)
    }
}
