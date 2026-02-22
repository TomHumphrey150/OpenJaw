import Foundation
import Testing
@testable import Telocare

struct OutcomeTrendDataBuilderTests {
    @Test func morningPointsFilterLastFourteenDaysAndSortAscending() throws {
        let builder = OutcomeTrendDataBuilder(
            calendar: fixedCalendar,
            now: try fixedDate("2026-02-22")
        )
        let states = [
            MorningState(
                nightId: "2026-02-22",
                globalSensation: 6,
                neckTightness: nil,
                jawSoreness: nil,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-22T08:00:00Z"
            ),
            MorningState(
                nightId: "2026-02-08",
                globalSensation: 4,
                neckTightness: nil,
                jawSoreness: nil,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-08T08:00:00Z"
            ),
            MorningState(
                nightId: "2026-02-09",
                globalSensation: 5,
                neckTightness: nil,
                jawSoreness: nil,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-09T08:00:00Z"
            ),
            MorningState(
                nightId: "2026-02-20",
                globalSensation: 7,
                neckTightness: nil,
                jawSoreness: nil,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-20T08:00:00Z"
            ),
        ]

        let points = builder.morningPoints(from: states, metric: .globalSensation)

        #expect(points.map { dateKey($0.date) } == ["2026-02-09", "2026-02-20", "2026-02-22"])
        #expect(points.map(\.value) == [5, 7, 6])
    }

    @Test func morningCompositeIgnoresMissingFields() {
        let builder = OutcomeTrendDataBuilder(calendar: fixedCalendar, now: nowDate)
        let states = [
            MorningState(
                nightId: "2026-02-22",
                globalSensation: 6,
                neckTightness: nil,
                jawSoreness: 4,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-22T08:00:00Z"
            ),
        ]

        let points = builder.morningPoints(from: states, metric: .composite)

        #expect(points.count == 1)
        #expect(points.first?.value == 5)
    }

    @Test func morningCompositeOmitsRecordsWithoutValues() {
        let builder = OutcomeTrendDataBuilder(calendar: fixedCalendar, now: nowDate)
        let states = [
            MorningState(
                nightId: "2026-02-22",
                globalSensation: nil,
                neckTightness: nil,
                jawSoreness: nil,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-22T08:00:00Z"
            ),
            MorningState(
                nightId: "2026-02-21",
                globalSensation: 4,
                neckTightness: nil,
                jawSoreness: nil,
                earFullness: nil,
                healthAnxiety: nil,
                createdAt: "2026-02-21T08:00:00Z"
            ),
        ]

        let points = builder.morningPoints(from: states, metric: .composite)

        #expect(points.map { dateKey($0.date) } == ["2026-02-21"])
        #expect(points.map(\.value) == [4])
    }

    @Test func nightMetricExtractionSupportsRateCountAndConfidence() {
        let builder = OutcomeTrendDataBuilder(calendar: fixedCalendar, now: nowDate)
        let outcomes = [
            NightOutcome(
                nightId: "2026-02-22",
                microArousalCount: 11,
                microArousalRatePerHour: 2.4,
                confidence: 0.73,
                totalSleepMinutes: 402,
                source: "wearable",
                createdAt: "2026-02-22T07:40:00Z"
            ),
        ]

        let ratePoints = builder.nightPoints(from: outcomes, metric: .microArousalRatePerHour)
        let countPoints = builder.nightPoints(from: outcomes, metric: .microArousalCount)
        let confidencePoints = builder.nightPoints(from: outcomes, metric: .confidence)

        #expect(ratePoints.first?.value == 2.4)
        #expect(countPoints.first?.value == 11)
        #expect(confidencePoints.first?.value == 0.73)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private var nowDate: Date {
        Date(timeIntervalSince1970: 1_771_718_400)
    }

    private func fixedDate(_ key: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = fixedCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else {
            throw DateParsingError.invalidDateKey
        }
        return date
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = fixedCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum DateParsingError: Error {
    case invalidDateKey
}
