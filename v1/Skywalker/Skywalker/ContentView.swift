//
//  ContentView.swift
//  Skywalker
//
//  Bruxism Biofeedback - Main app interface
//

import SwiftUI

struct ContentView: View {
    @State private var settings = AppSettings()
    @State private var watchService = WatchConnectivityService()
    @State private var eventLogger = EventLogger()
    @State private var webSocketService: WebSocketService
    @State private var interventionService = InterventionService()
    @State private var healthKitService = HealthKitService()

    @State private var showingSettings = false
    @State private var showingOvernightReport = false
    @State private var showingBruxismInfo = false
    @State private var isConnecting = false
    @State private var discoveryService = ServerDiscoveryService()
    @State private var connectionAttempted = false
    @State private var userDisconnected = false
    @State private var scanTimeoutExpired = false
    @State private var showCatchUpModal = false
    @State private var catchUpCards: [CatchUpCard] = []
    @State private var catchUpCurrentSection: CurrentSectionInfo?
    @Environment(\.scenePhase) private var scenePhase

    // Undo toast state
    @State private var showUndoToast = false
    @State private var lastCompletedIntervention: InterventionDefinition?

    // Quick check modal state (for notification tap)
    @State private var showQuickCheckModal = false
    @State private var quickCheckInterventionIds: [String] = []

    // Routine prompt state (for wake-up / wind-down)
    @State private var routineService = RoutineService()
    @State private var activeRoutinePrompt: RoutineService.RoutinePromptType?  // nil = no prompt shown

    init() {
        // Initialize WebSocketService with dependencies
        let watch = WatchConnectivityService()
        let logger = EventLogger()
        _webSocketService = State(wrappedValue: WebSocketService(watchService: watch, eventLogger: logger))
        _watchService = State(wrappedValue: watch)
        _eventLogger = State(wrappedValue: logger)
    }

    // MARK: - Last Night Filtered Data

    private var lastNightFilteredEvents: [JawClenchEvent] {
        let overnight = OvernightReportCalculator.filterEventsToOvernightWindow(
            events: eventLogger.events, forDate: Date()
        )
        // Only filter by sleep phases if we have sleep data
        guard healthKitService.isAuthorized,
              !healthKitService.sleepSamples.isEmpty else {
            return overnight
        }
        return OvernightReportCalculator.filterToSleepPhases(
            events: overnight,
            sleepSamples: healthKitService.sleepSamples
        )
    }

    private var lastNightSleepSeconds: TimeInterval {
        let stats = healthKitService.calculateStatistics(from: healthKitService.sleepSamples)
        return stats.totalAsleep > 0 ? stats.totalAsleep : 8 * 3600
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Compact header
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

                    // Daily habits / interventions
                    InterventionsSectionView(
                        interventionService: interventionService,
                        routineService: routineService,
                        onShowUndoToast: { definition in
                            lastCompletedIntervention = definition
                            showUndoToast = true
                        }
                    )
                    .padding(.horizontal)

                    // More section (About & Settings)
                    VStack(spacing: 0) {
                        Button(action: { showingBruxismInfo = true }) {
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

                        Button(action: { showingSettings = true }) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, watchService: watchService, eventLogger: eventLogger)
            }
            .sheet(isPresented: $showingOvernightReport) {
                OvernightReportView(eventLogger: eventLogger)
            }
            .sheet(isPresented: $showingBruxismInfo) {
                BruxismInfoView()
            }
            .sheet(isPresented: $showCatchUpModal, onDismiss: {
                // After catch-up modal is dismissed, check for routine prompt
                checkForRoutinePrompt()
            }) {
                CatchUpModalView(
                    interventionService: interventionService,
                    healthKitService: healthKitService,
                    cards: catchUpCards,
                    currentSectionInfo: catchUpCurrentSection
                )
            }
            .sheet(isPresented: $showQuickCheckModal) {
                QuickCheckModal(
                    interventionIds: quickCheckInterventionIds,
                    interventionService: interventionService
                )
            }
            .sheet(item: $activeRoutinePrompt) { prompt in
                RoutinePromptView(
                    promptType: prompt,
                    onConfirm: { handleRoutineConfirm(prompt) },
                    onDismiss: { activeRoutinePrompt = nil },
                    onLateStartOption: handleLateStartOption
                )
            }
            .onAppear {
                guard !connectionAttempted else { return }
                connectionAttempted = true

                if settings.serverURL != nil {
                    // Try to connect to saved server
                    connectToServer()

                    // If not connected after 3 seconds, start scanning
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if !webSocketService.isConnected && !userDisconnected {
                            discoveryService.startScanning()
                            startScanTimeout()
                        }
                    }
                } else {
                    // No saved server, start scanning immediately
                    discoveryService.startScanning()
                    startScanTimeout()
                }

                // Load HealthKit data for Last Night card
                Task {
                    await healthKitService.requestAuthorization()
                    if healthKitService.isAuthorized {
                        _ = try? await healthKitService.fetchLastNightSleep()
                    }
                }

                // Show catch-up modal first, then routine prompt after dismiss (or directly if no catch-up)
                refreshCatchUpModalOrRoutinePrompt()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    // Try catch-up modal first; if none, check for routine prompt
                    refreshCatchUpModalOrRoutinePrompt()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationTapped)) { notification in
                handleNotificationTap(notification)
            }
            .undoToast(
                isPresented: $showUndoToast,
                message: "Completed \(lastCompletedIntervention?.name ?? "habit")",
                duration: 4.0,
                onUndo: {
                    if let intervention = lastCompletedIntervention {
                        interventionService.removeLastCompletion(for: intervention.id)
                    }
                }
            )
        }
    }

    // MARK: - Catch-Up Modal

    /// Show catch-up modal if there are cards, otherwise check for routine prompt
    private func refreshCatchUpModalOrRoutinePrompt() {
        let cards = CatchUpDeckBuilder.build(interventionService: interventionService)
        catchUpCards = cards
        catchUpCurrentSection = CatchUpDeckBuilder.currentSectionInfo()

        if !cards.isEmpty {
            // Show catch-up modal first; routine prompt will be checked on dismiss
            showCatchUpModal = true
        } else {
            // No catch-up cards, check for routine prompt directly
            checkForRoutinePrompt()
        }
    }

    private func refreshCatchUpModal() {
        let cards = CatchUpDeckBuilder.build(interventionService: interventionService)
        catchUpCards = cards
        catchUpCurrentSection = CatchUpDeckBuilder.currentSectionInfo()
        showCatchUpModal = !cards.isEmpty
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
            Button(action: disconnectFromServer) {
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
            Button(action: {
                settings.serverIP = server.host
                settings.serverPort = server.port
                discoveryService.stopScanning()
                connectToServer()
            }) {
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
            Button(action: { showingSettings = true }) {
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
            Button(action: connectToServer) {
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

        return Button(action: { showingOvernightReport = true }) {
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

    // MARK: - Actions

    private func startScanTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if discoveryService.discoveredServers.isEmpty && !webSocketService.isConnected {
                scanTimeoutExpired = true
            }
        }
    }

    private func connectToServer() {
        guard let serverURL = settings.serverURL else {
            print("[UI] Invalid server URL")
            return
        }

        isConnecting = true
        webSocketService.connect(to: serverURL)

        // Start auto-reconnect
        webSocketService.startAutoReconnect(to: serverURL)

        // Update haptic pattern
        watchService.updateHapticPattern(settings.hapticPattern)

        // Simulate connection attempt UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isConnecting = false
        }
    }

    private func disconnectFromServer() {
        userDisconnected = true
        webSocketService.disconnect()
    }

    // MARK: - Notification Tap Handler

    private func handleNotificationTap(_ notification: Notification) {
        // Handle direct intervention IDs
        if let ids = notification.userInfo?["interventionIds"] as? [String], !ids.isEmpty {
            quickCheckInterventionIds = ids
            showQuickCheckModal = true
            return
        }

        // Handle reminder group ID - look up the group's intervention IDs
        if let groupId = notification.userInfo?["groupId"] as? String {
            // Find the reminder group and get its intervention IDs
            if let group = interventionService.reminderGroups.first(where: { $0.id.uuidString == groupId }) {
                quickCheckInterventionIds = group.interventionIds
                showQuickCheckModal = true
            }
        }
    }

    // MARK: - Routine Prompt Logic

    private func checkForRoutinePrompt() {
        activeRoutinePrompt = routineService.determinePrompt()
    }

    private func handleRoutineConfirm(_ prompt: RoutineService.RoutinePromptType) {
        switch prompt {
        case .wakeUp:
            routineService.startMorningRoutine()
        case .windDown:
            routineService.startWindDownRoutine()
        case .lateStartCatchUp:
            // This is handled by onLateStartOption
            break
        }
        activeRoutinePrompt = nil
    }

    private func handleLateStartOption(_ option: RoutineService.LateStartOption) {
        routineService.applyLateStartOption(option)
        activeRoutinePrompt = nil
    }
}

#Preview {
    ContentView()
}
