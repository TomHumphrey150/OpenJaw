import Foundation

struct OutcomeTrendPoint: Equatable, Identifiable {
    let date: Date
    let value: Double

    var id: Date {
        date
    }
}

enum MorningTrendMetric: String, CaseIterable, Identifiable {
    case composite
    case globalSensation
    case neckTightness
    case jawSoreness
    case earFullness
    case healthAnxiety
    case stressLevel

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .composite:
            return "Composite"
        case .globalSensation:
            return "Overall feeling"
        case .neckTightness:
            return "Neck tension"
        case .jawSoreness:
            return "Jaw soreness"
        case .earFullness:
            return "Ear fullness"
        case .healthAnxiety:
            return "Worry level"
        case .stressLevel:
            return "Stress level"
        }
    }
}

enum NightTrendMetric: String, CaseIterable, Identifiable {
    case microArousalRatePerHour
    case microArousalCount
    case confidence

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .microArousalRatePerHour:
            return "Arousal rate/hour"
        case .microArousalCount:
            return "Arousal count"
        case .confidence:
            return "Confidence"
        }
    }
}

struct OutcomeTrendDataBuilder {
    private let calendar: Calendar
    private let now: Date
    private let nightIDFormatter: DateFormatter

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        nightIDFormatter = formatter
    }

    func morningPoints(
        from morningStates: [MorningState],
        metric: MorningTrendMetric,
        windowDays: Int = 14
    ) -> [OutcomeTrendPoint] {
        guard let dateWindow = dateWindow(windowDays: windowDays) else {
            return []
        }

        let tuples = morningStates.compactMap { state -> (Date, Double)? in
            guard
                let date = localDayDate(for: state.nightId),
                dateWindow.contains(date),
                let value = morningValue(for: state, metric: metric)
            else {
                return nil
            }

            return (date, value)
        }

        return sortedDeduplicatedPoints(from: tuples)
    }

    func nightPoints(
        from nightOutcomes: [NightOutcome],
        metric: NightTrendMetric,
        windowDays: Int = 14
    ) -> [OutcomeTrendPoint] {
        guard let dateWindow = dateWindow(windowDays: windowDays) else {
            return []
        }

        let tuples = nightOutcomes.compactMap { outcome -> (Date, Double)? in
            guard
                let date = localDayDate(for: outcome.nightId),
                dateWindow.contains(date),
                let value = nightValue(for: outcome, metric: metric)
            else {
                return nil
            }

            return (date, value)
        }

        return sortedDeduplicatedPoints(from: tuples)
    }

    func nightPoints(
        from outcomeRecords: [OutcomeRecord],
        metric: NightTrendMetric,
        windowDays: Int = 14
    ) -> [OutcomeTrendPoint] {
        guard let dateWindow = dateWindow(windowDays: windowDays) else {
            return []
        }

        let tuples = outcomeRecords.compactMap { record -> (Date, Double)? in
            guard
                let date = localDayDate(for: record.id),
                dateWindow.contains(date),
                let value = nightValue(for: record, metric: metric)
            else {
                return nil
            }

            return (date, value)
        }

        return sortedDeduplicatedPoints(from: tuples)
    }

    private func dateWindow(windowDays: Int) -> Range<Date>? {
        let days = max(1, windowDays)
        let today = calendar.startOfDay(for: now)
        guard
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
            let end = calendar.date(byAdding: .day, value: 1, to: today)
        else {
            return nil
        }

        return start..<end
    }

    private func localDayDate(for nightID: String) -> Date? {
        guard let parsed = nightIDFormatter.date(from: nightID) else {
            return nil
        }

        return calendar.startOfDay(for: parsed)
    }

    private func morningValue(for state: MorningState, metric: MorningTrendMetric) -> Double? {
        switch metric {
        case .composite:
            let values = [
                state.globalSensation,
                state.neckTightness,
                state.jawSoreness,
                state.earFullness,
                state.healthAnxiety,
                state.stressLevel,
            ].compactMap { $0 }

            guard !values.isEmpty else {
                return nil
            }

            return values.reduce(0, +) / Double(values.count)
        case .globalSensation:
            return state.globalSensation
        case .neckTightness:
            return state.neckTightness
        case .jawSoreness:
            return state.jawSoreness
        case .earFullness:
            return state.earFullness
        case .healthAnxiety:
            return state.healthAnxiety
        case .stressLevel:
            return state.stressLevel
        }
    }

    private func nightValue(for outcome: NightOutcome, metric: NightTrendMetric) -> Double? {
        switch metric {
        case .microArousalRatePerHour:
            return outcome.microArousalRatePerHour
        case .microArousalCount:
            return outcome.microArousalCount
        case .confidence:
            return outcome.confidence
        }
    }

    private func nightValue(for record: OutcomeRecord, metric: NightTrendMetric) -> Double? {
        switch metric {
        case .microArousalRatePerHour:
            return record.microArousalRatePerHour
        case .microArousalCount:
            return record.microArousalCount
        case .confidence:
            return record.confidence
        }
    }

    private func sortedDeduplicatedPoints(from tuples: [(Date, Double)]) -> [OutcomeTrendPoint] {
        var valuesByDate: [Date: Double] = [:]
        for (date, value) in tuples {
            valuesByDate[date] = value
        }

        return valuesByDate
            .keys
            .sorted()
            .compactMap { date in
                valuesByDate[date].map { value in
                    OutcomeTrendPoint(date: date, value: value)
                }
            }
    }
}
