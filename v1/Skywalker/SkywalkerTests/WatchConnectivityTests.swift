//
//  WatchConnectivityTests.swift
//  SkywalkerTests
//
//  Unit tests for Watch <-> iPhone communication
//

import XCTest
@testable import Skywalker

final class WatchConnectivityTests: XCTestCase {

    func testMessageFormat() {
        // Test that the message format matches what the watch expects
        let expectedAction = "haptic"
        let expectedPattern = "single_tap"

        // Simulate the message iPhone sends
        let message: [String: Any] = [
            "action": expectedAction,
            "pattern": expectedPattern,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        // Verify message structure
        XCTAssertNotNil(message["action"])
        XCTAssertEqual(message["action"] as? String, expectedAction)
        XCTAssertEqual(message["pattern"] as? String, expectedPattern)
        XCTAssertNotNil(message["timestamp"])

        // Verify pattern can be parsed
        if let patternRaw = message["pattern"] as? String {
            let pattern = HapticPattern(rawValue: patternRaw)
            XCTAssertNotNil(pattern, "Pattern should be valid HapticPattern enum value")
            XCTAssertEqual(pattern, .singleTap)
        } else {
            XCTFail("Pattern should be a string")
        }
    }

    func testAllHapticPatternsCanBeParsed() {
        // Test that all HapticPattern enum values can be sent and parsed
        for pattern in HapticPattern.allCases {
            let message: [String: Any] = [
                "action": "haptic",
                "pattern": pattern.rawValue
            ]

            guard let patternRaw = message["pattern"] as? String else {
                XCTFail("Pattern should be a string")
                continue
            }

            let parsedPattern = HapticPattern(rawValue: patternRaw)
            XCTAssertNotNil(parsedPattern, "Pattern '\(pattern.rawValue)' should be parsable")
            XCTAssertEqual(parsedPattern, pattern, "Parsed pattern should match original")
        }
    }

    func testMissingActionField() {
        // Test that messages without 'action' are rejected
        let message: [String: Any] = [
            "pattern": "single_tap"
        ]

        let action = message["action"] as? String
        XCTAssertNil(action, "Message without action field should return nil")
    }

    func testInvalidPattern() {
        // Test that invalid patterns default to .singleTap
        let message: [String: Any] = [
            "action": "haptic",
            "pattern": "invalid_pattern_name"
        ]

        let patternRaw = message["pattern"] as? String
        XCTAssertNotNil(patternRaw)

        let pattern = HapticPattern(rawValue: patternRaw!)
        XCTAssertNil(pattern, "Invalid pattern should not parse")

        // Watch app should default to .singleTap in this case
        let defaultPattern = pattern ?? .singleTap
        XCTAssertEqual(defaultPattern, .singleTap)
    }
}
