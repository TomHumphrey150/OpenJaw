import Foundation
import Testing
@testable import Telocare

struct InputCompletionHistoryBuilderTests {
    @Test func entriesSortByNewestFirstAndChartEntriesSortAscending() {
        let builder = InputCompletionHistoryBuilder(maxDisplayEvents: 10)
        let events = [
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T08:00:00Z",
                source: .binaryCheck
            ),
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T10:00:00Z",
                source: .doseIncrement
            ),
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T09:00:00Z",
                source: .binaryCheck
            ),
        ]

        let entries = builder.entries(from: events)
        let chartEntries = builder.chartEntries(from: events)

        #expect(entries.map { $0.event.occurredAt } == [
            "2026-02-21T10:00:00Z",
            "2026-02-21T09:00:00Z",
            "2026-02-21T08:00:00Z",
        ])
        #expect(chartEntries.map { $0.event.occurredAt } == [
            "2026-02-21T08:00:00Z",
            "2026-02-21T09:00:00Z",
            "2026-02-21T10:00:00Z",
        ])
    }

    @Test func entriesDropInvalidTimestampValues() {
        let builder = InputCompletionHistoryBuilder(maxDisplayEvents: 10)
        let events = [
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "invalid-date",
                source: .binaryCheck
            ),
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T09:00:00Z",
                source: .binaryCheck
            ),
        ]

        let entries = builder.entries(from: events)

        #expect(entries.count == 1)
        #expect(entries.first?.event.occurredAt == "2026-02-21T09:00:00Z")
    }

    @Test func entriesRespectMaxDisplayWindow() {
        let builder = InputCompletionHistoryBuilder(maxDisplayEvents: 2)
        let events = [
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T08:00:00Z",
                source: .binaryCheck
            ),
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T09:00:00Z",
                source: .binaryCheck
            ),
            InterventionCompletionEvent(
                interventionId: "PPI_TX",
                occurredAt: "2026-02-21T10:00:00Z",
                source: .binaryCheck
            ),
        ]

        let entries = builder.entries(from: events)

        #expect(entries.count == 2)
        #expect(entries.map { $0.event.occurredAt } == [
            "2026-02-21T10:00:00Z",
            "2026-02-21T09:00:00Z",
        ])
    }
}
