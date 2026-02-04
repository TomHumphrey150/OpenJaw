//
//  RoutineAnchor.swift
//  Skywalker
//
//  OpenJaw - Data model for routine start times (wake-up / wind-down anchors)
//

import Foundation

enum RoutineType: String, Codable {
    case morning
    case windDown
}

struct RoutineAnchor: Codable, Equatable {
    let type: RoutineType
    let startedAt: Date
    let dayAnchor: Date  // Start of day this applies to (for reset logic)

    init(type: RoutineType, startedAt: Date = Date(), calendar: Calendar = .current) {
        self.type = type
        self.startedAt = startedAt
        self.dayAnchor = calendar.startOfDay(for: startedAt)
    }

    /// Check if this anchor is still valid (same logical day, resets at 4am)
    func isValid(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let resetHour = 4
        let nowHour = calendar.component(.hour, from: now)
        let startOfToday = calendar.startOfDay(for: now)

        // If it's before 4am, anchor from "yesterday" (previous logical day) is still valid
        if nowHour < resetHour {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
                return false
            }
            return calendar.isDate(dayAnchor, inSameDayAs: previousDay)
        }

        // After 4am, only today's anchors are valid
        return calendar.isDate(dayAnchor, inSameDayAs: startOfToday)
    }
}
