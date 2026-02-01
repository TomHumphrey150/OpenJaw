//
//  Intervention.swift
//  Skywalker
//
//  OpenJaw - Core intervention models for bruxism treatment tracking
//

import Foundation

// MARK: - Enums

import SwiftUI

enum HabitCategory: String, CaseIterable {
    case quickTasks = "Quick Tasks"
    case reminders = "Reminders"
    case rules = "Rules"

    static var displayOrder: [HabitCategory] {
        [.quickTasks, .reminders, .rules]
    }

    var icon: String {
        switch self {
        case .reminders: return "bell.fill"
        case .rules: return "checkmark.shield.fill"
        case .quickTasks: return "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .reminders: return .orange
        case .rules: return .blue
        case .quickTasks: return .purple
        }
    }
}

enum InterventionTier: Int, Codable, CaseIterable {
    case strong = 1    // Strong evidence
    case moderate = 2  // Moderate evidence
    case lower = 3     // Lower evidence

    var displayName: String {
        switch self {
        case .strong: return "Strong Evidence"
        case .moderate: return "Moderate Evidence"
        case .lower: return "Lower Evidence"
        }
    }

    var description: String {
        switch self {
        case .strong: return "Well-established treatments backed by clinical research"
        case .moderate: return "Promising approaches with growing research support"
        case .lower: return "Complementary practices with some anecdotal support"
        }
    }
}

enum InterventionFrequency: String, Codable, CaseIterable {
    case continuous    // Automatic/ongoing (e.g., biofeedback)
    case hourly        // Multiple times per day
    case daily         // Once per day
    case weekly        // Once per week
    case quarterly     // Every few months
    case asNeeded      // No fixed schedule

    var displayName: String {
        switch self {
        case .continuous: return "Continuous"
        case .hourly: return "Throughout the day"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .quarterly: return "Quarterly"
        case .asNeeded: return "As needed"
        }
    }
}

enum TrackingType: String, Codable, CaseIterable {
    case binary       // Done or not done
    case counter      // Number of times
    case timer        // Duration
    case checklist    // Multiple sub-items
    case appointment  // Scheduled appointment
    case automatic    // Tracked automatically by app

    var displayName: String {
        switch self {
        case .binary: return "Yes/No"
        case .counter: return "Count"
        case .timer: return "Duration"
        case .checklist: return "Checklist"
        case .appointment: return "Appointment"
        case .automatic: return "Automatic"
        }
    }
}

// MARK: - Intervention Definition

struct InterventionDefinition: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let emoji: String                   // Emoji for display
    let icon: String                    // SF Symbol name (fallback)
    let description: String
    let detailedDescription: String?
    let tier: InterventionTier
    let frequency: InterventionFrequency
    let trackingType: TrackingType
    let isRemindable: Bool
    let defaultReminderMinutes: Int?
    let externalLink: URL?
    let evidenceLevel: String?
    let evidenceSummary: String?
    let citationIds: [String]
    let roiTier: String?                // A/B/C/D/E
    let easeScore: Int?                 // 1-10
    let costRange: String?

    // Coding keys for JSON mapping
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, icon, description, detailedDescription
        case tier, frequency, trackingType, isRemindable, defaultReminderMinutes
        case externalLink, evidenceLevel, evidenceSummary, citationIds
        case roiTier, easeScore, costRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "✨"
        icon = try container.decode(String.self, forKey: .icon)
        description = try container.decode(String.self, forKey: .description)
        detailedDescription = try container.decodeIfPresent(String.self, forKey: .detailedDescription)

        // Decode tier from Int
        let tierInt = try container.decode(Int.self, forKey: .tier)
        tier = InterventionTier(rawValue: tierInt) ?? .lower

        // Decode frequency from String
        let frequencyString = try container.decode(String.self, forKey: .frequency)
        frequency = InterventionFrequency(rawValue: frequencyString) ?? .daily

        // Decode trackingType from String
        let trackingString = try container.decode(String.self, forKey: .trackingType)
        trackingType = TrackingType(rawValue: trackingString) ?? .binary

        isRemindable = try container.decode(Bool.self, forKey: .isRemindable)
        defaultReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultReminderMinutes)
        externalLink = try container.decodeIfPresent(URL.self, forKey: .externalLink)
        evidenceLevel = try container.decodeIfPresent(String.self, forKey: .evidenceLevel)
        evidenceSummary = try container.decodeIfPresent(String.self, forKey: .evidenceSummary)
        citationIds = try container.decodeIfPresent([String].self, forKey: .citationIds) ?? []
        roiTier = try container.decodeIfPresent(String.self, forKey: .roiTier)
        easeScore = try container.decodeIfPresent(Int.self, forKey: .easeScore)
        costRange = try container.decodeIfPresent(String.self, forKey: .costRange)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(icon, forKey: .icon)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(detailedDescription, forKey: .detailedDescription)
        try container.encode(tier.rawValue, forKey: .tier)
        try container.encode(frequency.rawValue, forKey: .frequency)
        try container.encode(trackingType.rawValue, forKey: .trackingType)
        try container.encode(isRemindable, forKey: .isRemindable)
        try container.encodeIfPresent(defaultReminderMinutes, forKey: .defaultReminderMinutes)
        try container.encodeIfPresent(externalLink, forKey: .externalLink)
        try container.encodeIfPresent(evidenceLevel, forKey: .evidenceLevel)
        try container.encodeIfPresent(evidenceSummary, forKey: .evidenceSummary)
        try container.encode(citationIds, forKey: .citationIds)
        try container.encodeIfPresent(roiTier, forKey: .roiTier)
        try container.encodeIfPresent(easeScore, forKey: .easeScore)
        try container.encodeIfPresent(costRange, forKey: .costRange)
    }

    // Legacy initializer for backward compatibility (used in previews/tests)
    init(
        id: String,
        name: String,
        emoji: String = "✨",
        icon: String,
        description: String,
        detailedDescription: String? = nil,
        tier: InterventionTier,
        frequency: InterventionFrequency,
        trackingType: TrackingType,
        isRemindable: Bool,
        defaultReminderMinutes: Int? = nil,
        externalLink: URL? = nil,
        evidenceLevel: String? = nil,
        evidenceSummary: String? = nil,
        citationIds: [String] = [],
        roiTier: String? = nil,
        easeScore: Int? = nil,
        costRange: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.icon = icon
        self.description = description
        self.detailedDescription = detailedDescription
        self.tier = tier
        self.frequency = frequency
        self.trackingType = trackingType
        self.isRemindable = isRemindable
        self.defaultReminderMinutes = defaultReminderMinutes
        self.externalLink = externalLink
        self.evidenceLevel = evidenceLevel
        self.evidenceSummary = evidenceSummary
        self.citationIds = citationIds
        self.roiTier = roiTier
        self.easeScore = easeScore
        self.costRange = costRange
    }

    static func == (lhs: InterventionDefinition, rhs: InterventionDefinition) -> Bool {
        lhs.id == rhs.id
    }

    var category: HabitCategory {
        if isRemindable {
            return .reminders
        } else if frequency == .daily {
            return .rules
        } else {
            return .quickTasks
        }
    }
}

// MARK: - User Intervention

struct UserIntervention: Identifiable, Codable {
    let id: UUID
    let interventionId: String          // References InterventionDefinition.id
    var isEnabled: Bool
    var reminderEnabled: Bool
    var reminderIntervalMinutes: Int
    var dateAdded: Date

    // Time selection for daily/weekly/weekday reminders
    var reminderHour: Int?              // 0-23, nil = use default (18 = 6 PM)
    var reminderMinute: Int?            // 0-59, nil = use default (0)
    var reminderWeekday: Int?           // 1-7 (Sun-Sat), for weekly only, nil = Sunday

    // Reminder grouping
    var reminderGroupId: UUID?          // If part of a group, references ReminderGroup.id

    init(interventionId: String, reminderIntervalMinutes: Int? = nil) {
        self.id = UUID()
        self.interventionId = interventionId
        self.isEnabled = true
        self.reminderEnabled = false
        self.reminderIntervalMinutes = reminderIntervalMinutes ?? 60
        self.dateAdded = Date()
        self.reminderHour = nil
        self.reminderMinute = nil
        self.reminderWeekday = nil
        self.reminderGroupId = nil
    }
}

// MARK: - Completion Value

enum CompletionValue: Codable, Equatable {
    case binary(Bool)
    case count(Int)
    case duration(TimeInterval)
    case checklist([String: Bool])

    var displayValue: String {
        switch self {
        case .binary(let done):
            return done ? "Done" : "Not done"
        case .count(let count):
            return "\(count)"
        case .duration(let seconds):
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        case .checklist(let items):
            let completed = items.values.filter { $0 }.count
            return "\(completed)/\(items.count)"
        }
    }
}

// MARK: - Intervention Completion

struct InterventionCompletion: Identifiable, Codable {
    let id: UUID
    let interventionId: String
    let timestamp: Date
    let value: CompletionValue

    init(interventionId: String, value: CompletionValue) {
        self.id = UUID()
        self.interventionId = interventionId
        self.timestamp = Date()
        self.value = value
    }
}

// MARK: - Reminder Group

/// Groups multiple interventions into a single combined reminder notification
struct ReminderGroup: Identifiable, Codable {
    let id: UUID
    var name: String                    // Auto-generated or user-customizable
    var interventionIds: [String]       // Member intervention IDs
    var intervalMinutes: Int            // Shared interval (uses shortest of grouped items)

    // Time settings (for daily/weekly/weekday intervals)
    var reminderHour: Int               // 0-23, default 18 (6 PM)
    var reminderMinute: Int             // 0-59, default 0
    var reminderWeekday: Int            // 1-7 (Sun-Sat), for weekly only, default 1 (Sunday)

    var dateCreated: Date

    init(
        name: String,
        interventionIds: [String],
        intervalMinutes: Int,
        reminderHour: Int = 18,
        reminderMinute: Int = 0,
        reminderWeekday: Int = 1
    ) {
        self.id = UUID()
        self.name = name
        self.interventionIds = interventionIds
        self.intervalMinutes = intervalMinutes
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.reminderWeekday = reminderWeekday
        self.dateCreated = Date()
    }

    /// Check if this group contains a specific intervention
    func contains(_ interventionId: String) -> Bool {
        interventionIds.contains(interventionId)
    }
}
