import Foundation

final class MuseFeatureFlagStore {
    static let key = "telocare.feature.muse.enabled"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> Bool {
        userDefaults.bool(forKey: Self.key)
    }

    func save(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Self.key)
    }
}
