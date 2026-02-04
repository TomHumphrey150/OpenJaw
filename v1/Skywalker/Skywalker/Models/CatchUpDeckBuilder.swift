//
//  CatchUpDeckBuilder.swift
//  Skywalker
//
//  Builds the Tinder-style catch-up card deck for past interventions.
//

import Foundation

struct CatchUpCard: Identifiable {
    let id: UUID
    let definition: InterventionDefinition
    let day: Date
    let section: TimeOfDaySection
    let interval: DateInterval
    let sectionLabel: String
    let healthHintType: HealthHintType?
    var count: Int

    init(
        definition: InterventionDefinition,
        day: Date,
        section: TimeOfDaySection,
        interval: DateInterval,
        sectionLabel: String,
        healthHintType: HealthHintType?,
        count: Int
    ) {
        self.id = UUID()
        self.definition = definition
        self.day = day
        self.section = section
        self.interval = interval
        self.sectionLabel = sectionLabel
        self.healthHintType = healthHintType
        self.count = count
    }
}

struct CurrentSectionInfo {
    let section: TimeOfDaySection
    let interval: DateInterval
    let remaining: TimeInterval
}

struct CatchUpDeckBuilder {
    private static let sectionOrderIndex: [TimeOfDaySection: Int] = {
        Dictionary(uniqueKeysWithValues: TimeOfDaySection.displayOrder.enumerated().map { ($1, $0) })
    }()

    static func build(
        interventionService: InterventionService,
        now: Date = Date(),
        lookbackHours: Int = 24
    ) -> [CatchUpCard] {
        let calendar = Calendar.current
        let lookbackStart = now.addingTimeInterval(TimeInterval(-lookbackHours * 3600))
        let startDay = calendar.startOfDay(for: lookbackStart)
        let endDay = calendar.startOfDay(for: now)

        var days: [Date] = []
        var dayCursor = startDay
        while dayCursor <= endDay {
            days.append(dayCursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else {
                break
            }
            dayCursor = next
        }

        let definitions = interventionService.enabledInterventions().compactMap { interventionService.interventionDefinition(for: $0) }

        var cards: [CatchUpCard] = []

        for day in days {
            for definition in definitions {
                guard shouldInclude(definition.trackingType) else { continue }
                guard let section = catchUpSection(for: definition) else { continue }
                guard let interval = section.dateInterval(on: day) else { continue }

                guard interval.end <= now else { continue }
                guard interval.end >= lookbackStart else { continue }

                if interventionService.isCompleted(on: day, interventionId: definition.id) {
                    continue
                }
                if interventionService.decisionStatus(for: definition.id, on: day) != nil {
                    continue
                }

                let label = sectionLabel(for: section, day: day, now: now, calendar: calendar)
                let hintType = healthHintType(for: definition)
                let count = definition.trackingType == .counter ? 1 : 0

                cards.append(
                    CatchUpCard(
                        definition: definition,
                        day: day,
                        section: section,
                        interval: interval,
                        sectionLabel: label,
                        healthHintType: hintType,
                        count: count
                    )
                )
            }
        }

        return cards.sorted { lhs, rhs in
            if !calendar.isDate(lhs.day, inSameDayAs: rhs.day) {
                return lhs.day < rhs.day
            }
            let lhsIndex = sectionOrderIndex[lhs.section] ?? 0
            let rhsIndex = sectionOrderIndex[rhs.section] ?? 0
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.definition.name.localizedCaseInsensitiveCompare(rhs.definition.name) == .orderedAscending
        }
    }

    static func currentSectionInfo(now: Date = Date()) -> CurrentSectionInfo? {
        guard let current = TimeOfDaySection.currentSection(now: now) else {
            return nil
        }
        guard let interval = current.dateInterval(on: now) else {
            return nil
        }
        let remaining = max(0, interval.end.timeIntervalSince(now))
        return CurrentSectionInfo(section: current, interval: interval, remaining: remaining)
    }

    private static func catchUpSection(for definition: InterventionDefinition) -> TimeOfDaySection? {
        let sections = definition.timeOfDaySections.filter { $0 != .anytime }
        guard !sections.isEmpty else { return nil }

        return sections.sorted { lhs, rhs in
            let lhsIndex = sectionOrderIndex[lhs] ?? 0
            let rhsIndex = sectionOrderIndex[rhs] ?? 0
            return lhsIndex < rhsIndex
        }.last
    }

    private static func shouldInclude(_ trackingType: TrackingType) -> Bool {
        switch trackingType {
        case .binary, .counter, .timer:
            return true
        case .checklist, .appointment, .automatic:
            return false
        }
    }

    private static func sectionLabel(
        for section: TimeOfDaySection,
        day: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        if calendar.isDateInToday(day) {
            return "\(section.displayName) today"
        }
        if calendar.isDateInYesterday(day) {
            return "\(section.displayName) yesterday"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "\(section.displayName) \(formatter.string(from: day))"
    }

    private static func healthHintType(for definition: InterventionDefinition) -> HealthHintType? {
        if definition.id == "exercise_timing" {
            return .exercise
        }
        if definition.id == "stress_reduction" || definition.id == "mindfulness_prebed" {
            return .mindfulness
        }
        if definition.id == "hydration_target" || definition.id.hasPrefix("hydration_") {
            return .water
        }
        return nil
    }
}
