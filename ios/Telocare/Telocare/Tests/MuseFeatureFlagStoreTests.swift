import Foundation
import Testing
@testable import Telocare

struct MuseFeatureFlagStoreTests {
    @Test func loadDefaultsToFalseWhenUnset() throws {
        let suiteName = "MuseFeatureFlagStoreTests.default.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = MuseFeatureFlagStore(userDefaults: defaults)
        #expect(store.load() == false)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func saveAndLoadRoundTrip() throws {
        let suiteName = "MuseFeatureFlagStoreTests.save.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = MuseFeatureFlagStore(userDefaults: defaults)
        store.save(true)
        #expect(store.load() == true)

        store.save(false)
        #expect(store.load() == false)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
