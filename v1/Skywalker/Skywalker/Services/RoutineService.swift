//
//  RoutineService.swift
//  Skywalker
//
//  OpenJaw - Business logic for routine management (wake-up / wind-down anchors)
//

import Foundation
import Observation

@Observable
@MainActor
class RoutineService {
    var morningAnchor: RoutineAnchor?
    var windDownAnchor: RoutineAnchor?

    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let morningAnchorKey = "routine.morningAnchor"
    private let windDownAnchorKey = "routine.windDownAnchor"

    init() {
        loadAnchors()
        cleanupStaleAnchors()
    }

    // MARK: - Anchor Management

    func startMorningRoutine() {
        morningAnchor = RoutineAnchor(type: .morning)
        saveAnchors()
    }

    func startWindDownRoutine() {
        windDownAnchor = RoutineAnchor(type: .windDown)
        saveAnchors()
    }

    var isMorningStartedToday: Bool {
        morningAnchor?.isValid() ?? false
    }

    var isWindDownStartedToday: Bool {
        windDownAnchor?.isValid() ?? false
    }

    /// Returns the anchor time for a given section, if routine was started
    func anchor(for section: TimeOfDaySection) -> Date? {
        switch section {
        case .morning:
            return morningAnchor?.isValid() == true ? morningAnchor?.startedAt : nil
        case .preBed:
            return windDownAnchor?.isValid() == true ? windDownAnchor?.startedAt : nil
        default:
            return nil
        }
    }

    // MARK: - Prompt Logic

    enum RoutinePromptType: Equatable, Identifiable {
        case wakeUp
        case windDown
        case lateStartCatchUp(minutesUntilAfternoon: Int)

        var id: String {
            switch self {
            case .wakeUp: return "wakeUp"
            case .windDown: return "windDown"
            case .lateStartCatchUp(let mins): return "lateStart-\(mins)"
            }
        }
    }

    func determinePrompt(now: Date = Date(), calendar: Calendar = .current) -> RoutinePromptType? {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        // After 9pm (21:00): wind-down prompt (if not started)
        if hour >= 21 && !isWindDownStartedToday {
            return .windDown
        }

        // After 4am, before 12pm: wake-up prompt (if not started)
        if hour >= 4 && hour < 12 && !isMorningStartedToday {
            // Calculate if this is a "late start" scenario (after 10am)
            if hour >= 10 {
                // Calculate minutes until 12pm (afternoon start)
                let minutesUntil12 = (12 - hour) * 60 - minute
                return .lateStartCatchUp(minutesUntilAfternoon: max(0, minutesUntil12))
            }
            return .wakeUp
        }

        return nil
    }

    // MARK: - Late Start Options

    enum LateStartOption {
        case fullMorning       // Run full routine, push afternoon back
        case compressedMorning // Fit essential items into remaining time
        case skipMorning       // Skip to afternoon
    }

    func applyLateStartOption(_ option: LateStartOption) {
        switch option {
        case .fullMorning, .compressedMorning:
            // Both options start the morning routine
            // The view layer can differentiate based on time remaining
            startMorningRoutine()
        case .skipMorning:
            // Don't start morning routine - show afternoon flat list
            break
        }
    }

    // MARK: - Persistence

    private func saveAnchors() {
        if let morning = morningAnchor,
           let data = try? encoder.encode(morning) {
            userDefaults.set(data, forKey: morningAnchorKey)
        } else {
            userDefaults.removeObject(forKey: morningAnchorKey)
        }

        if let windDown = windDownAnchor,
           let data = try? encoder.encode(windDown) {
            userDefaults.set(data, forKey: windDownAnchorKey)
        } else {
            userDefaults.removeObject(forKey: windDownAnchorKey)
        }
    }

    private func loadAnchors() {
        if let data = userDefaults.data(forKey: morningAnchorKey),
           let anchor = try? decoder.decode(RoutineAnchor.self, from: data) {
            morningAnchor = anchor
        }

        if let data = userDefaults.data(forKey: windDownAnchorKey),
           let anchor = try? decoder.decode(RoutineAnchor.self, from: data) {
            windDownAnchor = anchor
        }
    }

    /// Clean up anchors from previous days (called on init and 4am reset)
    private func cleanupStaleAnchors() {
        if morningAnchor?.isValid() == false {
            morningAnchor = nil
        }
        if windDownAnchor?.isValid() == false {
            windDownAnchor = nil
        }
        saveAnchors()
    }

    /// Reset anchors (called at 4am daily or when checking for stale data)
    func resetDailyAnchors() {
        cleanupStaleAnchors()
    }
}
