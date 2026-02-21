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
    }

    @Test func rejectsPlaceholderConfigValues() {
        #expect(throws: AppConfigurationError.self) {
            try AppConfiguration(
                supabaseURLString: "YOUR_SUPABASE_URL",
                supabasePublishableKey: "sb_publishable_test"
            )
        }
    }
}
