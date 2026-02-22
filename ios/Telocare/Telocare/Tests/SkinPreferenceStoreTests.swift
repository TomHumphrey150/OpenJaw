import Foundation
import Testing
@testable import Telocare

struct SkinPreferenceStoreTests {
    @Test func savesAndLoadsSkinID() throws {
        let suiteName = "SkinPreferenceStoreTests.save.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = SkinPreferenceStore(userDefaults: defaults)
        store.save(.garden)

        #expect(store.load() == .garden)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func invalidStoredValueReturnsNil() throws {
        let suiteName = "SkinPreferenceStoreTests.invalid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("not-a-valid-skin", forKey: SkinPreferenceStore.key)

        let store = SkinPreferenceStore(userDefaults: defaults)
        #expect(store.load() == nil)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
