//
//  Intervention.swift
//  Skywalker
//
//  OpenJaw - Core intervention models for bruxism treatment tracking
//

import Foundation

// MARK: - Enums

import SwiftUI

enum TimeOfDaySection: String, CaseIterable, Codable {
    case morning
    case afternoon
    case evening
    case preBed
    case anytime

    static var displayOrder: [TimeOfDaySection] {
        [.morning, .afternoon, .evening, .preBed, .anytime]
    }

    static let schedule: [(section: TimeOfDaySection, startHour: Int, endHour: Int)] = [
        (.morning, 5, 12),
        (.afternoon, 12, 17),
        (.evening, 17, 21),
        (.preBed, 21, 5)  // Wraps around midnight (9pm to 5am)
    ]

    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .preBed: return "Pre-Bed"
        case .anytime: return "Anytime"
        }
    }

    var timeWindow: String {
        switch self {
        case .morning: return "5am-12pm"
        case .afternoon: return "12pm-5pm"
        case .evening: return "5pm-9pm"
        case .preBed: return "9pm-11pm"
        case .anytime: return "All day"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .preBed: return "moon.stars.fill"
        case .anytime: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning: return .yellow
        case .afternoon: return .orange
        case .evening: return .pink
        case .preBed: return .purple
        case .anytime: return .blue
        }
    }

    func dateInterval(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        guard self != .anytime else {
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        }

        guard let schedule = Self.schedule.first(where: { $0.section == self }) else {
            return nil
        }

        let startOfDay = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .hour, value: schedule.startHour, to: startOfDay) else {
            return nil
        }

        // Handle midnight wrap (e.g., preBed 21:00 to 05:00 next day)
        var endDay = startOfDay
        if schedule.endHour < schedule.startHour {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
                return nil
            }
            endDay = nextDay
        }

        guard let end = calendar.date(byAdding: .hour, value: schedule.endHour, to: endDay) else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    static func currentSection(now: Date = Date(), calendar: Calendar = .current) -> TimeOfDaySection? {
        let hour = calendar.component(.hour, from: now)

        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        case 21..<24, 0..<5:
            // 9pm to 4:59am = pre-bed (covers late night)
            return .preBed
        default:
            return nil
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

enum EnergyLevel: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var icon: String {
        switch self {
        case .low: return "battery.25"
        case .medium: return "battery.50"
        case .high: return "battery.100"
        }
    }

    /// Numeric value for comparison (1=low, 2=medium, 3=high)
    var numericValue: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    /// Check if this energy level is at or below the given maximum
    func isWithin(max: EnergyLevel) -> Bool {
        numericValue <= max.numericValue
    }
}

// MARK: - Sub-Block (Time sub-windows within sections - RELATIVE to routine anchor)

enum SubBlock: String, CaseIterable, Codable, Comparable {
    // Morning sub-blocks (relative to wake-up tap)
    case morningBlock1     // +0 to +60 min (Wake-Up)
    case morningBlock2     // +60 to +150 min (Mid-Morning)
    case morningBlock3     // +150 to +240 min (Late Morning)

    // Pre-Bed sub-blocks (relative to wind-down tap)
    case preBedWindDown    // +0 to +60 min
    case preBedPreSleep    // +60 to +90 min
    case preBedLightsOut   // +90 to +120 min (includes end-of-day reflections)

    var parentSection: TimeOfDaySection {
        switch self {
        case .morningBlock1, .morningBlock2, .morningBlock3:
            return .morning
        case .preBedWindDown, .preBedPreSleep, .preBedLightsOut:
            return .preBed
        }
    }

    var displayName: String {
        switch self {
        case .morningBlock1: return "Wake-Up"
        case .morningBlock2: return "Mid-Morning"
        case .morningBlock3: return "Late Morning"
        case .preBedWindDown: return "Wind-Down"
        case .preBedPreSleep: return "Pre-Sleep"
        case .preBedLightsOut: return "Lights Out"
        }
    }

    /// Relative schedule as (startMinutes, endMinutes) from anchor time
    var relativeSchedule: (startMinutes: Int, endMinutes: Int) {
        switch self {
        case .morningBlock1: return (0, 60)      // +0 to +1hr
        case .morningBlock2: return (60, 150)    // +1hr to +2.5hr
        case .morningBlock3: return (150, 240)   // +2.5hr to +4hr
        case .preBedWindDown: return (0, 60)     // +0 to +1hr
        case .preBedPreSleep: return (60, 90)    // +1hr to +1.5hr
        case .preBedLightsOut: return (90, 120)  // +1.5hr to +2hr
        }
    }

    /// Order for sequential comparison (lower = earlier in routine)
    var order: Int {
        switch self {
        case .morningBlock1: return 0
        case .morningBlock2: return 1
        case .morningBlock3: return 2
        case .preBedWindDown: return 3
        case .preBedPreSleep: return 4
        case .preBedLightsOut: return 5
        }
    }

    static func < (lhs: SubBlock, rhs: SubBlock) -> Bool {
        lhs.order < rhs.order
    }

    /// Get all sub-blocks for a given parent section
    /// NOTE: Afternoon and Evening no longer have sub-blocks (flat lists only)
    static func subBlocks(for section: TimeOfDaySection) -> [SubBlock] {
        switch section {
        case .morning:
            return [.morningBlock1, .morningBlock2, .morningBlock3]
        case .preBed:
            return [.preBedWindDown, .preBedPreSleep, .preBedLightsOut]
        case .afternoon, .evening, .anytime:
            return [] // No sub-blocks for these sections
        }
    }

    /// Calculate time window display string relative to anchor
    /// Returns something like "7:00-8:00am" based on when user started routine
    func timeWindowDisplay(anchoredAt anchor: Date, calendar: Calendar = .current) -> String {
        let sched = relativeSchedule
        guard let start = calendar.date(byAdding: .minute, value: sched.startMinutes, to: anchor),
              let end = calendar.date(byAdding: .minute, value: sched.endMinutes, to: anchor) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        let startStr = formatter.string(from: start)

        formatter.dateFormat = "h:mma"
        let endStr = formatter.string(from: end).lowercased()

        return "\(startStr)-\(endStr)"
    }

    /// Get date interval for this sub-block given an anchor time
    func dateInterval(anchoredAt anchor: Date, calendar: Calendar = .current) -> DateInterval? {
        let sched = relativeSchedule
        guard let start = calendar.date(byAdding: .minute, value: sched.startMinutes, to: anchor),
              let end = calendar.date(byAdding: .minute, value: sched.endMinutes, to: anchor) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    /// Get current sub-block based on elapsed time from anchor
    static func currentSubBlock(
        for section: TimeOfDaySection,
        anchoredAt anchor: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SubBlock? {
        let elapsed = now.timeIntervalSince(anchor) / 60  // minutes since anchor

        for subBlock in subBlocks(for: section) {
            let sched = subBlock.relativeSchedule
            if elapsed >= Double(sched.startMinutes) && elapsed < Double(sched.endMinutes) {
                return subBlock
            }
        }

        return nil  // Past all sub-blocks or before routine started
    }

    // MARK: - Legacy Support (for transition period)

    /// Legacy: Get date interval on a specific day (uses default anchor times)
    /// This is kept for backward compatibility but should be phased out
    func dateInterval(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        // Use default anchor times: 7am for morning, 9pm for pre-bed
        let startOfDay = calendar.startOfDay(for: day)
        let defaultAnchor: Date?

        switch parentSection {
        case .morning:
            defaultAnchor = calendar.date(byAdding: .hour, value: 7, to: startOfDay)
        case .preBed:
            defaultAnchor = calendar.date(byAdding: .hour, value: 21, to: startOfDay)
        default:
            return nil
        }

        guard let anchor = defaultAnchor else { return nil }
        return dateInterval(anchoredAt: anchor, calendar: calendar)
    }
}

// MARK: - Block Visibility State

enum BlockVisibility {
    case hidden      // Not yet available (previous blocks incomplete)
    case active      // Current block, fully visible and interactive
    case completed   // All items done, collapsed view
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
    let timeOfDay: [TimeOfDaySection]
    let defaultOrder: Int?

    // Capacity filtering fields
    let estimatedDurationMinutes: Int?  // Estimated time to complete (1-60 min)
    let energyLevel: EnergyLevel?       // Required energy level (low/medium/high)
    let liteVariantDurationMinutes: Int? // Shorter duration for "lite" mode (timer-based only)

    // Coding keys for JSON mapping
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, icon, description, detailedDescription
        case tier, frequency, trackingType, isRemindable, defaultReminderMinutes
        case externalLink, evidenceLevel, evidenceSummary, citationIds
        case roiTier, easeScore, costRange, timeOfDay, defaultOrder
        case estimatedDurationMinutes, energyLevel, liteVariantDurationMinutes
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
        defaultOrder = try container.decodeIfPresent(Int.self, forKey: .defaultOrder)

        if let timeOfDayArray = try? container.decode([TimeOfDaySection].self, forKey: .timeOfDay) {
            timeOfDay = timeOfDayArray
        } else if let timeOfDaySingle = try? container.decode(TimeOfDaySection.self, forKey: .timeOfDay) {
            timeOfDay = [timeOfDaySingle]
        } else {
            timeOfDay = [.anytime]
        }

        // Capacity filtering fields
        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        energyLevel = try container.decodeIfPresent(EnergyLevel.self, forKey: .energyLevel)
        liteVariantDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .liteVariantDurationMinutes)
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
        try container.encode(timeOfDay, forKey: .timeOfDay)
        try container.encodeIfPresent(defaultOrder, forKey: .defaultOrder)

        // Capacity filtering fields
        try container.encodeIfPresent(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encodeIfPresent(energyLevel, forKey: .energyLevel)
        try container.encodeIfPresent(liteVariantDurationMinutes, forKey: .liteVariantDurationMinutes)
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
        costRange: String? = nil,
        timeOfDay: [TimeOfDaySection] = [.anytime],
        defaultOrder: Int? = nil,
        estimatedDurationMinutes: Int? = nil,
        energyLevel: EnergyLevel? = nil,
        liteVariantDurationMinutes: Int? = nil
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
        self.timeOfDay = timeOfDay
        self.defaultOrder = defaultOrder
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.energyLevel = energyLevel
        self.liteVariantDurationMinutes = liteVariantDurationMinutes
    }

    static func == (lhs: InterventionDefinition, rhs: InterventionDefinition) -> Bool {
        lhs.id == rhs.id
    }

    var timeOfDaySections: [TimeOfDaySection] {
        timeOfDay.isEmpty ? [.anytime] : timeOfDay
    }

    /// Items that are "end of day" reflections - these appear in the final pre-bed block
    /// These are anytime items that ask "did you do X today?" rather than "do X now"
    var isEndOfDayReflection: Bool {
        let reflectionIds = [
            "reflux_trigger_avoidance",
            "strict_diet_phase",
            "caffeine_limit",
            "alcohol_limit"
        ]
        return timeOfDaySections.contains(.anytime) && reflectionIds.contains(id)
    }

    // MARK: - Capacity Filtering Helpers

    /// Duration in minutes with fallback default (5 min)
    var durationMinutes: Int {
        estimatedDurationMinutes ?? 5
    }

    /// Energy level with fallback default (medium)
    var requiredEnergy: EnergyLevel {
        energyLevel ?? .medium
    }

    /// Duration display string (e.g., "5 min")
    var durationDisplay: String {
        let mins = durationMinutes
        return mins == 1 ? "1 min" : "\(mins) min"
    }

    /// Check if this intervention fits within the given capacity constraints
    func fitsCapacity(availableMinutes: Int, maxEnergy: EnergyLevel) -> Bool {
        durationMinutes <= availableMinutes && requiredEnergy.isWithin(max: maxEnergy)
    }

    /// Whether this intervention has a lite (shorter) variant available
    var hasLiteVariant: Bool {
        liteVariantDurationMinutes != nil && trackingType == .timer
    }

    /// Duration for lite variant with fallback to regular duration
    var liteDurationMinutes: Int {
        liteVariantDurationMinutes ?? durationMinutes
    }

    /// Assign this intervention to a sub-block within its section
    /// Only morning and pre-bed have sub-blocks; afternoon/evening are flat lists
    func assignedSubBlock(for section: TimeOfDaySection) -> SubBlock? {
        // End-of-day reflections always go to final pre-bed block
        if isEndOfDayReflection {
            return .preBedLightsOut
        }

        // Only morning and pre-bed have sub-blocks
        guard section == .morning || section == .preBed else { return nil }

        let subBlocks = SubBlock.subBlocks(for: section)
        guard !subBlocks.isEmpty else { return nil }

        // Use defaultOrder to distribute across sub-blocks
        // Orders 10-100 → Block 1, 101-200 → Block 2, 201+ → Block 3
        let order = defaultOrder ?? 100
        let bucketIndex: Int
        if order <= 100 {
            bucketIndex = 0
        } else if order <= 200 {
            bucketIndex = min(1, subBlocks.count - 1)
        } else {
            bucketIndex = min(2, subBlocks.count - 1)
        }

        return subBlocks[bucketIndex]
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

    init(interventionId: String, value: CompletionValue, timestamp: Date = Date()) {
        self.id = UUID()
        self.interventionId = interventionId
        self.timestamp = timestamp
        self.value = value
    }
}

// MARK: - Decision Tracking

enum InterventionDecisionStatus: String, Codable {
    case done
    case skipped
}

struct InterventionDecision: Identifiable, Codable {
    let id: UUID
    let interventionId: String
    let day: Date
    var status: InterventionDecisionStatus
    var count: Int?
    var updatedAt: Date

    init(
        interventionId: String,
        day: Date,
        status: InterventionDecisionStatus,
        count: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = UUID()
        self.interventionId = interventionId
        self.day = day
        self.status = status
        self.count = count
        self.updatedAt = updatedAt
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
