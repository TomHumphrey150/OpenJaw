//
//  UserCapacity.swift
//  Skywalker
//
//  OpenJaw - User's available time and energy for current session
//

import Foundation

/// Represents the user's available capacity for a session
struct UserCapacity {
    /// Available time in minutes
    let availableMinutes: Int

    /// Maximum energy level the user wants to spend
    let maxEnergy: EnergyLevel

    /// Predefined time options for the capacity dial
    static let timeOptions: [Int] = [5, 10, 15, 30, 60]

    /// Display text for a time option
    static func timeDisplayText(minutes: Int) -> String {
        if minutes >= 60 {
            return "60+"
        }
        return "\(minutes)"
    }

    /// Check if an intervention fits within this capacity
    func fits(intervention: InterventionDefinition) -> Bool {
        intervention.fitsCapacity(availableMinutes: availableMinutes, maxEnergy: maxEnergy)
    }

    /// Filter a list of interventions to those that fit this capacity
    func filter(interventions: [InterventionDefinition]) -> [InterventionDefinition] {
        interventions.filter { fits(intervention: $0) }
    }

    /// Calculate total duration of interventions that fit
    func totalDuration(of interventions: [InterventionDefinition]) -> Int {
        filter(interventions: interventions).reduce(0) { $0 + $1.durationMinutes }
    }
}
