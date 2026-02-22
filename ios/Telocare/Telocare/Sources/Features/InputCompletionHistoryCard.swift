import Charts
import Foundation
import SwiftUI

struct InputCompletionHistoryEntry: Equatable, Identifiable {
    let id: Int
    let event: InterventionCompletionEvent
    let date: Date
}

struct InputCompletionHistoryBuilder {
    let maxDisplayEvents: Int

    private let internetDateFormatter: ISO8601DateFormatter
    private let fractionalDateFormatter: ISO8601DateFormatter

    init(maxDisplayEvents: Int = 200) {
        self.maxDisplayEvents = max(1, maxDisplayEvents)

        let internetDateFormatter = ISO8601DateFormatter()
        internetDateFormatter.formatOptions = [.withInternetDateTime]
        internetDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let fractionalDateFormatter = ISO8601DateFormatter()
        fractionalDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        self.internetDateFormatter = internetDateFormatter
        self.fractionalDateFormatter = fractionalDateFormatter
    }

    func entries(from events: [InterventionCompletionEvent]) -> [InputCompletionHistoryEntry] {
        let parsed = events.compactMap { event -> (InterventionCompletionEvent, Date)? in
            guard let date = parsedDate(from: event.occurredAt) else {
                return nil
            }
            return (event, date)
        }

        let sorted = parsed.sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.occurredAt > rhs.0.occurredAt
            }
            return lhs.1 > rhs.1
        }

        return sorted
            .prefix(maxDisplayEvents)
            .enumerated()
            .map { index, tuple in
                InputCompletionHistoryEntry(id: index, event: tuple.0, date: tuple.1)
            }
    }

    func chartEntries(from events: [InterventionCompletionEvent]) -> [InputCompletionHistoryEntry] {
        entries(from: events)
            .sorted { lhs, rhs in
                lhs.date < rhs.date
            }
    }

    private func parsedDate(from value: String) -> Date? {
        if let fractional = fractionalDateFormatter.date(from: value) {
            return fractional
        }

        return internetDateFormatter.date(from: value)
    }
}

struct InputCompletionHistoryCard: View {
    let events: [InterventionCompletionEvent]
    let recentListLimit: Int

    private let builder: InputCompletionHistoryBuilder

    init(
        events: [InterventionCompletionEvent],
        builder: InputCompletionHistoryBuilder = InputCompletionHistoryBuilder(),
        recentListLimit: Int = 5
    ) {
        self.events = events
        self.builder = builder
        self.recentListLimit = max(1, recentListLimit)
    }

    var body: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(
                    title: "Completion history",
                    subtitle: "When you marked this intervention as done"
                )

                HStack {
                    Text("Latest")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                    Spacer()
                    Text(latestTimestampText)
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.charcoal)
                }

                Chart(chartHistoryEntries) { entry in
                    PointMark(
                        x: .value("Timestamp", entry.date),
                        y: .value("Completion", 0)
                    )
                    .foregroundStyle(color(for: entry.event.source))
                    .symbolSize(60)
                }
                .frame(height: 150)
                .chartYAxis(.hidden)
                .chartYScale(domain: -1...1)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                }
                .accessibilityIdentifier(AccessibilityID.exploreInputCompletionHistoryChart)
                .accessibilityLabel("Intervention completion history chart")
                .accessibilityValue(chartAccessibilityValue)

                if historyEntries.isEmpty {
                    Text("No completion events yet. New check-ins will appear with date and time.")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        ForEach(recentEntries) { entry in
                            HStack {
                                Text(sourceLabel(for: entry.event.source))
                                    .font(TelocareTheme.Typography.caption)
                                    .foregroundStyle(color(for: entry.event.source))
                                Spacer()
                                Text(formatted(entry.date))
                                    .font(TelocareTheme.Typography.caption)
                                    .foregroundStyle(TelocareTheme.warmGray)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historyEntries: [InputCompletionHistoryEntry] {
        builder.entries(from: events)
    }

    private var chartHistoryEntries: [InputCompletionHistoryEntry] {
        builder.chartEntries(from: events)
    }

    private var recentEntries: [InputCompletionHistoryEntry] {
        Array(historyEntries.prefix(recentListLimit))
    }

    private var latestEntry: InputCompletionHistoryEntry {
        historyEntries[0]
    }

    private var latestTimestampText: String {
        guard let latest = historyEntries.first else {
            return "None"
        }

        return formatted(latest.date)
    }

    private var chartAccessibilityValue: String {
        guard let latest = historyEntries.first else {
            return "No completion events yet."
        }

        return "\(historyEntries.count) events. Latest \(formatted(latest.date))."
    }

    private func color(for source: InterventionCompletionEventSource) -> Color {
        switch source {
        case .binaryCheck:
            return TelocareTheme.coral
        case .doseIncrement:
            return TelocareTheme.success
        }
    }

    private func sourceLabel(for source: InterventionCompletionEventSource) -> String {
        switch source {
        case .binaryCheck:
            return "Check-in"
        case .doseIncrement:
            return "Dose +"
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
