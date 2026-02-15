//
//  OvernightReportView.swift
//  Skywalker
//
//  OpenJaw - Overnight report with sleep phase correlation and trends
//

import SwiftUI
import Charts

struct OvernightReportView: View {
    var eventLogger: EventLogger
    @State private var healthKitService = HealthKitService()

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var includeAwakeTime = false  // false = sleep only (default)
    @State private var selectedDate = Date()
    @State private var selectedTab = 0  // 0 = Tonight, 1 = Week
    @State private var showingHealthKitAlert = false
    @State private var weekSleepData: [Date: [HealthKitService.SleepSample]] = [:]

    private var overnightEvents: [JawClenchEvent] {
        OvernightReportCalculator.filterEventsToOvernightWindow(
            events: eventLogger.events,
            forDate: selectedDate
        )
    }

    private var filteredEvents: [JawClenchEvent] {
        // If including awake time, return all events
        guard !includeAwakeTime else { return overnightEvents }

        // Otherwise filter to sleep phases only
        return OvernightReportCalculator.filterToSleepPhases(
            events: overnightEvents,
            sleepSamples: healthKitService.sleepSamples
        )
    }

    private var sleepStatistics: HealthKitService.SleepStatistics {
        healthKitService.calculateStatistics(from: healthKitService.sleepSamples)
    }

    private var hasDetailedSleepStages: Bool {
        healthKitService.sleepSamples.contains { sample in
            [.core, .deep, .rem].contains(sample.phase)
        }
    }

    // Previous night's data for comparison
    private var previousNightEvents: [JawClenchEvent] {
        let calendar = Calendar.current
        guard let previousDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) else {
            return []
        }
        return OvernightReportCalculator.filterEventsToOvernightWindow(
            events: eventLogger.events,
            forDate: previousDate
        )
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Loading sleep data...")
                            .padding(.top, 50)
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(error)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task { await loadData() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 50)
                    } else {
                        // Tab selector
                        Picker("View", selection: $selectedTab) {
                            Text("Last Night").tag(0)
                            Text("Trends").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if selectedTab == 0 {
                            // Tonight view
                            enhancedSummarySection

                            // Event clustering insight
                            eventClusteringSection

                            // Timeline Chart
                            timelineSection
                        } else {
                            // Trends view
                            weekOverWeekSection

                            weekTrendSection

                            // Weekly statistics
                            weekStatisticsSection
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: generateReportText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task {
                await loadData()
            }
            .alert("Health Data Required", isPresented: $showingHealthKitAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To filter events by sleep phases, OpenJaw needs access to your sleep data from Apple Health.")
            }
        }
    }

    // MARK: - Sections

    private var enhancedSummarySection: some View {
        VStack(spacing: 16) {
            // Large hero stat
            VStack(spacing: 4) {
                Text("\(filteredEvents.count)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(severityColor)

                Text("events last night")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Comparison to previous night
                if !previousNightEvents.isEmpty {
                    let diff = filteredEvents.count - previousNightEvents.count
                    HStack(spacing: 4) {
                        Image(systemName: diff <= 0 ? "arrow.down" : "arrow.up")
                        Text("\(abs(diff)) vs previous night")
                    }
                    .font(.caption)
                    .foregroundColor(diff <= 0 ? .green : .red)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)

            // Secondary stats row
            HStack(spacing: 20) {
                StatCard(
                    title: "Per Hour",
                    value: String(format: "%.1f", eventsPerHour),
                    icon: "clock",
                    color: eventsPerHourColor
                )

                StatCard(
                    title: "Sleep",
                    value: formatDuration(sleepStatistics.totalAsleep),
                    icon: "bed.double.fill",
                    color: .purple
                )
            }

            // Filter toggle
            Toggle("Include awake time", isOn: Binding(
                get: { includeAwakeTime },
                set: { newValue in
                    if newValue && !healthKitService.isAuthorized {
                        // User trying to enable filter but no HealthKit access
                        showingHealthKitAlert = true
                    } else {
                        includeAwakeTime = newValue
                    }
                }
            ))
            .font(.subheadline)
            .disabled(!healthKitService.isAuthorized)
        }
        .padding()
        .background(severityColor.opacity(0.08))
        .cornerRadius(12)
    }

    private var severityColor: Color {
        let rate = eventsPerHour
        if rate < 2 { return .green }
        if rate < 5 { return .yellow }
        return .red
    }

    private var eventsPerHourColor: Color {
        let rate = eventsPerHour
        if rate < 2 { return .green }
        if rate < 5 { return .orange }
        return .red
    }

    private var eventClusteringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.blue)
                Text("Event Clustering")
                    .font(.headline)
            }

            if let peak = findPeakEventWindow() {
                EventClusteringContent(
                    peakStart: peak.start,
                    peakEnd: peak.end,
                    peakCount: peak.count,
                    insight: generateClusteringInsight(peakStart: peak.start)
                )
            } else {
                Text("Events were spread evenly throughout the night")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var weekTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                Text("7-Day Trend")
                    .font(.headline)
            }

            let weekData = getWeekData()

            if !weekData.isEmpty {
                Chart(weekData, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Events", day.count)
                    )
                    .foregroundStyle(day.date.isToday ? Color.blue : Color.blue.opacity(0.5))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .frame(height: 180)

                // Trend indicator
                if let trend = calculateTrend(from: weekData) {
                    HStack(spacing: 8) {
                        Image(systemName: trend.isImproving ? "arrow.down.right" : "arrow.up.right")
                            .foregroundColor(trend.isImproving ? .green : .red)
                        Text(trend.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("Not enough data for weekly trend")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(height: 180)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var weekStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Statistics")
                .font(.headline)

            let weekData = getWeekData()
            let totalEvents = weekData.reduce(0) { $0 + $1.count }
            let avgEvents = weekData.isEmpty ? 0 : Double(totalEvents) / Double(weekData.count)
            let minEvents = weekData.min(by: { $0.count < $1.count })?.count ?? 0
            let maxEvents = weekData.max(by: { $0.count < $1.count })?.count ?? 0

            HStack(spacing: 16) {
                WeekStatCard(title: "Average", value: String(format: "%.0f", avgEvents), subtitle: "events/night")
                WeekStatCard(title: "Best", value: "\(minEvents)", subtitle: "events")
                WeekStatCard(title: "Worst", value: "\(maxEvents)", subtitle: "events")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var weekOverWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                Text("Week-over-Week")
                    .font(.headline)
            }

            if let comparison = calculateWeekOverWeekComparison() {
                // Large KPI display
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: comparison.isImproving ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(.title)
                                .foregroundColor(comparison.isImproving ? .green : .red)
                            Text("\(comparison.percentChange)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(comparison.isImproving ? .green : .red)
                        }
                        Text(comparison.isImproving ? "fewer events than last week" : "more events than last week")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // This week vs last week
                    VStack(alignment: .trailing, spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("This week")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(comparison.thisWeekTotal)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Last week")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(comparison.lastWeekTotal)")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            } else {
                Text("Need at least 2 weeks of data for comparison")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func calculateWeekOverWeekComparison() -> (isImproving: Bool, percentChange: Int, thisWeekTotal: Int, lastWeekTotal: Int)? {
        let calendar = Calendar.current

        // This week's events (last 7 days)
        var thisWeekTotal = 0
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: selectedDate) else { continue }
            let events = OvernightReportCalculator.filterEventsToOvernightWindow(
                events: eventLogger.events,
                forDate: date
            )
            thisWeekTotal += events.count
        }

        // Last week's events (7-14 days ago)
        var lastWeekTotal = 0
        for dayOffset in 7..<14 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: selectedDate) else { continue }
            let events = OvernightReportCalculator.filterEventsToOvernightWindow(
                events: eventLogger.events,
                forDate: date
            )
            lastWeekTotal += events.count
        }

        guard lastWeekTotal > 0 else { return nil }

        let percentChange = Int(Double(thisWeekTotal - lastWeekTotal) / Double(lastWeekTotal) * 100)
        let isImproving = percentChange <= 0

        return (isImproving: isImproving, percentChange: abs(percentChange), thisWeekTotal: thisWeekTotal, lastWeekTotal: lastWeekTotal)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            if !healthKitService.sleepSamples.isEmpty || !filteredEvents.isEmpty {
                timelineChart
                    .frame(height: 200)
            } else {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .red, label: "Awake")
                legendItem(color: .blue, label: "Core")
                legendItem(color: .purple, label: "Deep")
                legendItem(color: .green, label: "REM")
            }
            .font(.caption)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var timelineChart: some View {
        Chart {
            // Sleep phase bands
            ForEach(healthKitService.sleepSamples) { sample in
                RectangleMark(
                    xStart: .value("Start", sample.startDate),
                    xEnd: .value("End", sample.endDate),
                    yStart: .value("Low", 0),
                    yEnd: .value("High", 1)
                )
                .foregroundStyle(colorForPhase(sample.phase).opacity(0.3))
            }

            // Jaw clench events as points
            ForEach(filteredEvents) { event in
                PointMark(
                    x: .value("Time", event.timestamp),
                    y: .value("Event", 0.5)
                )
                .foregroundStyle(.red)
                .symbolSize(50)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine()
            }
        }
        .chartYAxis(.hidden)
    }

    private var phaseBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Events by Sleep Phase")
                .font(.headline)

            if !hasDetailedSleepStages {
                Text("Detailed sleep stages require Apple Watch")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }

            let breakdown = eventsByPhase()

            ForEach(breakdown.sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { phase, count in
                HStack {
                    Circle()
                        .fill(colorForPhase(phase))
                        .frame(width: 12, height: 12)
                    Text(phase.rawValue)
                    Spacer()
                    Text("\(count)")
                        .fontWeight(.semibold)
                }
            }

            if breakdown.isEmpty {
                Text("No events recorded")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Distribution (15-min windows)")
                .font(.headline)

            let histogram = eventHistogram()

            if !histogram.isEmpty {
                Chart(histogram, id: \.time) { bucket in
                    BarMark(
                        x: .value("Time", bucket.time),
                        y: .value("Events", bucket.count)
                    )
                    .foregroundStyle(.blue)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 150)
            } else {
                Text("No events to display")
                    .foregroundColor(.secondary)
                    .frame(height: 150)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Helper Views

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Data Methods

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        // Request HealthKit authorization
        await healthKitService.requestAuthorization()

        if !healthKitService.isAuthorized {
            // Still show data, just can't filter by sleep
            // Force includeAwakeTime since we can't filter without sleep data
            includeAwakeTime = true
            isLoading = false
            return
        }

        // Fetch sleep data for the full week
        let calendar = Calendar.current
        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: selectedDate) else { continue }
            do {
                let samples = try await healthKitService.fetchSleepData(for: date)
                weekSleepData[calendar.startOfDay(for: date)] = samples
            } catch {
                print("[OvernightReport] Failed to fetch sleep data for \(date): \(error)")
            }
        }

        // Set current day's samples for other uses
        healthKitService.sleepSamples = weekSleepData[calendar.startOfDay(for: selectedDate)] ?? []

        isLoading = false
    }

    private var eventsPerHour: Double {
        OvernightReportCalculator.eventsPerHour(
            eventCount: filteredEvents.count,
            totalSleepSeconds: sleepStatistics.totalAsleep
        )
    }

    private func eventsByPhase() -> [HealthKitService.SleepPhase: Int] {
        OvernightReportCalculator.eventsByPhase(
            events: overnightEvents,
            sleepSamples: healthKitService.sleepSamples
        )
    }

    private func eventHistogram() -> [(time: Date, count: Int)] {
        OvernightReportCalculator.eventHistogram(events: filteredEvents, bucketMinutes: 15)
    }

    private func colorForPhase(_ phase: HealthKitService.SleepPhase) -> Color {
        switch phase {
        case .inBed: return .gray
        case .awake: return .red
        case .core: return .blue
        case .deep: return .purple
        case .rem: return .green
        case .asleepUnspecified: return .blue
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    // MARK: - Week Data

    private func getWeekData() -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        var data: [(date: Date, count: Int)] = []

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: selectedDate) else { continue }
            var events = OvernightReportCalculator.filterEventsToOvernightWindow(
                events: eventLogger.events,
                forDate: date
            )

            // Apply sleep filter if not including awake time AND we have sleep data
            if !includeAwakeTime, let sleepSamples = weekSleepData[calendar.startOfDay(for: date)] {
                events = OvernightReportCalculator.filterToSleepPhases(
                    events: events,
                    sleepSamples: sleepSamples
                )
            }

            data.append((date: date, count: events.count))
        }

        return data
    }

    private func calculateTrend(from data: [(date: Date, count: Int)]) -> (isImproving: Bool, description: String)? {
        guard data.count >= 3 else { return nil }

        let firstHalf = data.prefix(data.count / 2)
        let secondHalf = data.suffix(data.count / 2)

        let firstAvg = Double(firstHalf.reduce(0) { $0 + $1.count }) / Double(firstHalf.count)
        let secondAvg = Double(secondHalf.reduce(0) { $0 + $1.count }) / Double(secondHalf.count)

        let diff = secondAvg - firstAvg
        let isImproving = diff <= 0

        if abs(diff) < 1 {
            return (isImproving: true, description: "Events have remained stable")
        } else if isImproving {
            return (isImproving: true, description: "Events have decreased by \(Int(abs(diff))) on average")
        } else {
            return (isImproving: false, description: "Events have increased by \(Int(diff)) on average")
        }
    }

    // MARK: - Clustering Analysis

    private func findPeakEventWindow() -> (start: Date, end: Date, count: Int)? {
        guard filteredEvents.count >= 3 else { return nil }

        // Group events into 1-hour windows
        var windows: [Date: Int] = [:]
        let calendar = Calendar.current

        for event in filteredEvents {
            let hour = calendar.component(.hour, from: event.timestamp)
            var components = calendar.dateComponents([.year, .month, .day], from: event.timestamp)
            components.hour = hour
            if let windowStart = calendar.date(from: components) {
                windows[windowStart, default: 0] += 1
            }
        }

        // Find the window with most events
        guard let peak = windows.max(by: { $0.value < $1.value }),
              peak.value >= 2 else { return nil }

        guard let windowEnd = calendar.date(byAdding: .hour, value: 1, to: peak.key) else { return nil }

        return (start: peak.key, end: windowEnd, count: peak.value)
    }

    private func generateClusteringInsight(peakStart: Date) -> String? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: peakStart)

        // Check which sleep phase this corresponds to
        let matchingPhase = healthKitService.sleepSamples.first { sample in
            sample.startDate <= peakStart && sample.endDate >= peakStart
        }

        if let phase = matchingPhase {
            switch phase.phase {
            case .rem:
                return "This coincides with REM sleep, when bruxism is often most active"
            case .deep:
                return "Deep sleep events may indicate significant muscle tension"
            case .core:
                return "Light sleep is a common time for jaw clenching"
            default:
                break
            }
        }

        // Time-based insights
        if hour >= 2 && hour < 5 {
            return "The early morning hours often show increased bruxism activity"
        } else if hour >= 5 && hour < 7 {
            return "Events near wake time may be related to sleep stage transitions"
        }

        return nil
    }

    private func generateReportText() -> String {
        var report = "OpenJaw Overnight Report\n"
        report += "Date: \(selectedDate.formatted(date: .abbreviated, time: .omitted))\n\n"

        report += "Summary:\n"
        report += "- Total events: \(filteredEvents.count)\n"
        report += "- Events per hour: \(String(format: "%.1f", eventsPerHour))\n"
        report += "- Total sleep: \(formatDuration(sleepStatistics.totalAsleep))\n\n"

        report += "Events by phase:\n"
        for (phase, count) in eventsByPhase().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            report += "- \(phase.rawValue): \(count)\n"
        }

        return report
    }
}

// MARK: - Supporting Views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

private struct WeekStatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}

private struct EventClusteringContent: View {
    let peakStart: Date
    let peakEnd: Date
    let peakCount: Int
    let insight: String?

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most events occurred between")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Text("\(timeFormatter.string(from: peakStart)) - \(timeFormatter.string(from: peakEnd))")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(peakCount) events")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }

            if let insight = insight {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text(insight)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Date Extension

private extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}

#Preview {
    OvernightReportView(eventLogger: EventLogger())
}
