//
//  SleepBiofeedbackTab.swift
//  Skywalker
//
//  OpenJaw - Tab for sleep biofeedback monitoring and settings
//

import SwiftUI

struct SleepBiofeedbackTab: View {
    @Bindable var settings: AppSettings
    @Bindable var watchService: WatchConnectivityService
    @Bindable var webSocketService: WebSocketService
    @Bindable var eventLogger: EventLogger
    @Bindable var healthKitService: HealthKitService
    @Bindable var discoveryService: ServerDiscoveryService

    @Binding var isConnecting: Bool
    @Binding var scanTimeoutExpired: Bool

    var onShowSettings: () -> Void
    var onShowOvernightReport: () -> Void
    var onShowBruxismInfo: () -> Void
    var onConnectToServer: () -> Void
    var onDisconnectFromServer: () -> Void
    var onDiscoveredServerConnect: (ServerDiscoveryService.DiscoveredServer) -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Text("🦷")
                            .font(.title2)
                        Text("OpenJaw")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 20)

                    // Biofeedback section
                    biofeedbackSection
                        .padding(.horizontal)

                    // More section (About & Settings)
                    VStack(spacing: 0) {
                        Button(action: onShowBruxismInfo) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                Text("About Bruxism")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }

                        Divider()
                            .padding(.leading, 52)

                        Button(action: onShowSettings) {
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                                Text("Settings")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // MARK: - Biofeedback Section

    private var biofeedbackSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.purple)
                Text("Sleep Biofeedback")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Status indicators
            VStack(spacing: 0) {
                // Server status
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(webSocketService.isConnected ? .green : .secondary)
                        .frame(width: 24)
                    Text("Relay Server")
                        .font(.subheadline)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(webSocketService.isConnected ? Color.green : Color.red.opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text(webSocketService.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, 52)

                // Watch status
                HStack {
                    Image(systemName: "applewatch")
                        .foregroundColor(watchService.watchReachable ? .green : .secondary)
                        .frame(width: 24)
                    Text("Apple Watch")
                        .font(.subheadline)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(watchService.watchReachable ? Color.green : (watchService.isPaired ? Color.orange : Color.red.opacity(0.8)))
                            .frame(width: 8, height: 8)
                        Text(watchStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            // Connection controls
            connectionSection
                .padding(16)

            Divider()

            // Progress section
            progressCardContent
                .padding(16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var watchStatusText: String {
        if watchService.watchReachable {
            return "Ready"
        } else if watchService.isPaired {
            return "Paired"
        } else {
            return "Not Paired"
        }
    }

    // MARK: - Connection Section

    @ViewBuilder
    private var connectionSection: some View {
        if webSocketService.isConnected {
            // Connected - show disconnect button
            Button(action: onDisconnectFromServer) {
                HStack {
                    Image(systemName: "stop.circle.fill")
                    Text("Disconnect from OpenJaw Relay")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        } else if !discoveryService.discoveredServers.isEmpty {
            // Server found - show connect button
            let server = discoveryService.discoveredServers[0]
            Button(action: { onDiscoveredServerConnect(server) }) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                    Text(isConnecting ? "Connecting..." : "Connect to \(server.name)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isConnecting)
        } else if scanTimeoutExpired {
            // Timeout expired, no server found
            Button(action: onShowSettings) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Server Not Found – Fix in Settings")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        } else if discoveryService.isScanning {
            // Still scanning
            HStack {
                ProgressView()
                Text("Scanning for servers...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if settings.serverURL != nil {
            // Has saved server but not scanning - show connect button
            Button(action: onConnectToServer) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                    Text(isConnecting ? "Connecting..." : "Connect to OpenJaw Relay")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isConnecting)
        }
    }

    // MARK: - Progress Card

    private var progressCardContent: some View {
        let weekData = getWeekData()
        let weekComparison = calculateWeekOverWeekChange()
        let stats = calculateWeekStats()

        return Button(action: onShowOvernightReport) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.blue)
                    Text("Progress")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()

                    // Main KPI badge
                    if let comparison = weekComparison {
                        HStack(spacing: 2) {
                            Image(systemName: comparison.isImproving ? "arrow.down" : "arrow.up")
                                .font(.caption2)
                            Text("\(comparison.percentText)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(comparison.isImproving ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((comparison.isImproving ? Color.green : Color.red).opacity(0.15))
                        .cornerRadius(8)
                    }
                }

                // Stats row with mini chart
                HStack(spacing: 16) {
                    // Mini 7-day bar chart
                    if !weekData.isEmpty {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(weekData, id: \.date) { day in
                                VStack(spacing: 2) {
                                    miniBar(count: day.count, maxCount: weekData.map(\.count).max() ?? 1)
                                    Text(dayInitial(for: day.date))
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(height: 45)
                    }

                    Spacer()

                    // KPI stats
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("Avg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f", stats.avgEvents))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        HStack(spacing: 4) {
                            Text("Best")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(stats.bestNight)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Footer with comparison text
                HStack {
                    if let comparison = weekComparison {
                        Text(comparison.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Tap to view detailed report")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
        }
        .foregroundColor(.primary)
    }

    /// Mini bar for the 7-day chart
    @ViewBuilder
    private func miniBar(count: Int, maxCount: Int) -> some View {
        let height = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) * 30 : 0
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.blue)
            .frame(width: 24, height: max(height, 2))
    }

    /// Get the day initial (M, T, W, etc.)
    private func dayInitial(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"  // Single letter day
        return formatter.string(from: date)
    }

    /// Get week data for the mini chart
    private func getWeekData() -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        var data: [(date: Date, count: Int)] = []

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let events = OvernightReportCalculator.filterEventsToOvernightWindow(
                events: eventLogger.events,
                forDate: date
            )
            data.append((date: date, count: events.count))
        }

        return data
    }

    /// Calculate week-over-week change
    private func calculateWeekOverWeekChange() -> (isImproving: Bool, text: String, percentText: String)? {
        let calendar = Calendar.current

        // This week's events (last 7 days)
        var thisWeekTotal = 0
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let events = OvernightReportCalculator.filterEventsToOvernightWindow(
                events: eventLogger.events,
                forDate: date
            )
            thisWeekTotal += events.count
        }

        // Last week's events (7-14 days ago)
        var lastWeekTotal = 0
        for dayOffset in 7..<14 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let events = OvernightReportCalculator.filterEventsToOvernightWindow(
                events: eventLogger.events,
                forDate: date
            )
            lastWeekTotal += events.count
        }

        // Need some data in both weeks to compare
        guard lastWeekTotal > 0 else { return nil }

        let percentChange = Double(thisWeekTotal - lastWeekTotal) / Double(lastWeekTotal) * 100
        let isImproving = percentChange <= 0
        let percentText = "\(Int(abs(percentChange)))%"

        if abs(percentChange) < 5 {
            return (isImproving: true, text: "Stable vs last week", percentText: "~0%")
        } else {
            return (isImproving: isImproving, text: "\(isImproving ? "Down" : "Up") \(Int(abs(percentChange)))% vs last week", percentText: percentText)
        }
    }

    /// Calculate week stats (avg, best night)
    private func calculateWeekStats() -> (avgEvents: Double, bestNight: Int) {
        let weekData = getWeekData()
        guard !weekData.isEmpty else { return (0, 0) }

        let total = weekData.reduce(0) { $0 + $1.count }
        let avg = Double(total) / Double(weekData.count)
        let best = weekData.map(\.count).min() ?? 0

        return (avgEvents: avg, bestNight: best)
    }
}

#Preview {
    SleepBiofeedbackTab(
        settings: AppSettings(),
        watchService: WatchConnectivityService(),
        webSocketService: WebSocketService(watchService: WatchConnectivityService(), eventLogger: EventLogger()),
        eventLogger: EventLogger(),
        healthKitService: HealthKitService(),
        discoveryService: ServerDiscoveryService(),
        isConnecting: Binding.constant(false),
        scanTimeoutExpired: Binding.constant(false),
        onShowSettings: {},
        onShowOvernightReport: {},
        onShowBruxismInfo: {},
        onConnectToServer: {},
        onDisconnectFromServer: {},
        onDiscoveredServerConnect: { _ in }
    )
}
