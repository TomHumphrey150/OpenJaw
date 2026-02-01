//
//  HapticEngine.swift
//  Skywalker-Watch Watch App
//
//  Bruxism Biofeedback - Haptic feedback engine for Apple Watch
//

import Foundation
import WatchKit
import SwiftUI

@MainActor
class HapticEngine {

    func play(_ pattern: HapticPattern) {
        print("[HapticEngine] Playing pattern: \(pattern.displayName)")

        switch pattern {
        case .singleTap:
            playSingleTap()
        case .doubleTap:
            playDoubleTap()
        case .gentleRamp:
            playGentleRamp()
        case .customPattern:
            playCustom()
        }
    }

    // MARK: - Haptic Patterns

    private func playSingleTap() {
        // Try multiple approaches
        WKInterfaceDevice.current().play(.notification)
        print("[HapticEngine] WKInterfaceDevice.play(.notification) called")

        // Also try other haptic types
        WKInterfaceDevice.current().play(.success)
        print("[HapticEngine] WKInterfaceDevice.play(.success) called")

        print("[HapticEngine] ✅ Single tap completed")
    }

    private func playDoubleTap() {
        WKInterfaceDevice.current().play(.notification)

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            WKInterfaceDevice.current().play(.notification)
        }

        print("[HapticEngine] Double tap played")
        print("[HapticEngine] ✅ Double tap initiated (async completion)")
    }

    private func playGentleRamp() {
        // Gentle ramp: start with click, then notification
        WKInterfaceDevice.current().play(.click)

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            WKInterfaceDevice.current().play(.directionUp)

            try? await Task.sleep(for: .milliseconds(200))
            WKInterfaceDevice.current().play(.notification)
        }

        print("[HapticEngine] Gentle ramp played")
        print("[HapticEngine] ✅ Gentle ramp initiated (async completion)")
    }

    private func playCustom() {
        // Custom pattern: series of clicks with escalating intensity
        WKInterfaceDevice.current().play(.click)

        Task {
            try? await Task.sleep(for: .milliseconds(150))
            WKInterfaceDevice.current().play(.click)

            try? await Task.sleep(for: .milliseconds(150))
            WKInterfaceDevice.current().play(.directionUp)

            try? await Task.sleep(for: .milliseconds(150))
            WKInterfaceDevice.current().play(.notification)
        }

        print("[HapticEngine] Custom pattern played")
        print("[HapticEngine] ✅ Custom pattern initiated (async completion)")
    }
}
