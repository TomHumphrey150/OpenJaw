//
//  AppSettings.swift
//  Skywalker
//
//  OpenJaw - App settings and persistence
//

import Foundation
import Observation

@Observable
@MainActor
class AppSettings {
    private let defaults = UserDefaults.standard

    // Server connection settings
    var serverIP: String {
        didSet {
            defaults.set(serverIP, forKey: "serverIP")
        }
    }

    var serverPort: Int {
        didSet {
            defaults.set(serverPort, forKey: "serverPort")
        }
    }

    // Haptic settings
    var hapticPattern: HapticPattern {
        didSet {
            defaults.set(hapticPattern.rawValue, forKey: "hapticPattern")
        }
    }

    // Notification settings
    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    var quietHoursStart: Int {
        didSet {
            defaults.set(quietHoursStart, forKey: "quietHoursStart")
        }
    }

    var quietHoursEnd: Int {
        didSet {
            defaults.set(quietHoursEnd, forKey: "quietHoursEnd")
        }
    }

    // Computed properties
    var serverURL: URL? {
        return URL(string: "ws://\(serverIP):\(serverPort)")
    }

    init() {
        // Load saved settings or use defaults
        let savedIP = defaults.string(forKey: "serverIP") ?? "192.168.1.43"
        let savedPort = defaults.integer(forKey: "serverPort")
        let savedPattern: HapticPattern

        if let patternRaw = defaults.string(forKey: "hapticPattern"),
           let pattern = HapticPattern(rawValue: patternRaw) {
            savedPattern = pattern
        } else {
            savedPattern = .singleTap
        }

        // Notification settings with defaults
        let savedNotificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        let savedQuietHoursStart = defaults.object(forKey: "quietHoursStart") as? Int ?? 22  // 10 PM
        let savedQuietHoursEnd = defaults.object(forKey: "quietHoursEnd") as? Int ?? 8       // 8 AM

        self.serverIP = savedIP
        self.serverPort = savedPort == 0 ? 8765 : savedPort
        self.hapticPattern = savedPattern
        self.notificationsEnabled = savedNotificationsEnabled
        self.quietHoursStart = savedQuietHoursStart
        self.quietHoursEnd = savedQuietHoursEnd
    }

    func resetToDefaults() {
        serverIP = "192.168.1.43"
        serverPort = 8765
        hapticPattern = .singleTap
        notificationsEnabled = true
        quietHoursStart = 22
        quietHoursEnd = 8
    }
}
