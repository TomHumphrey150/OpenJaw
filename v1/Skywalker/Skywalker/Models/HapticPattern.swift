//
//  HapticPattern.swift
//  Skywalker
//
//  Bruxism Biofeedback - Haptic pattern definitions
//

import Foundation

enum HapticPattern: String, Codable, CaseIterable, Identifiable {
    case singleTap = "single_tap"
    case doubleTap = "double_tap"
    case gentleRamp = "gentle_ramp"
    case customPattern = "custom_pattern"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleTap:
            return "Single Tap"
        case .doubleTap:
            return "Double Tap"
        case .gentleRamp:
            return "Gentle Ramp"
        case .customPattern:
            return "Custom Pattern"
        }
    }

    var description: String {
        switch self {
        case .singleTap:
            return "One quick vibration"
        case .doubleTap:
            return "Two quick vibrations"
        case .gentleRamp:
            return "Gradually increasing intensity"
        case .customPattern:
            return "User-defined pattern"
        }
    }
}
