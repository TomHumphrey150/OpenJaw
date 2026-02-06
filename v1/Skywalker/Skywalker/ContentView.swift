//
//  ContentView.swift
//  Skywalker
//
//  Bruxism Biofeedback - Main app interface with TabView navigation
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

    // Tab selection
    @State private var selectedTab = 0

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

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Daily Plan (Primary)
            DailyPlanTab(
                interventionService: interventionService,
                routineService: routineService,
                onShowUndoToast: { definition in
                    lastCompletedIntervention = definition
                    showUndoToast = true
                }
            )
            .tabItem {
                Label("Today", systemImage: "leaf.fill")
            }
            .tag(0)

            // Tab 2: Sleep Biofeedback
            SleepBiofeedbackTab(
                settings: settings,
                watchService: watchService,
                webSocketService: webSocketService,
                eventLogger: eventLogger,
                healthKitService: healthKitService,
                discoveryService: discoveryService,
                isConnecting: $isConnecting,
                scanTimeoutExpired: $scanTimeoutExpired,
                onShowSettings: { showingSettings = true },
                onShowOvernightReport: { showingOvernightReport = true },
                onShowBruxismInfo: { showingBruxismInfo = true },
                onConnectToServer: connectToServer,
                onDisconnectFromServer: disconnectFromServer,
                onDiscoveredServerConnect: { server in
                    settings.serverIP = server.host
                    settings.serverPort = server.port
                    discoveryService.stopScanning()
                    connectToServer()
                }
            )
            .tabItem {
                Label("Sleep", systemImage: "waveform.path.ecg")
            }
            .tag(1)
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

    // MARK: - Catch-Up Modal

    /// Show catch-up modal if there are cards, otherwise check for routine prompt
    private func refreshCatchUpModalOrRoutinePrompt() {
        let cards = CatchUpDeckBuilder.build(interventionService: interventionService)
        catchUpCards = cards
        catchUpCurrentSection = CatchUpDeckBuilder.currentSectionInfo()

        if !cards.isEmpty {
            // Delay modal presentation to next runloop to ensure state propagates
            DispatchQueue.main.async {
                showCatchUpModal = true
            }
        } else {
            // No catch-up cards, check for routine prompt directly
            checkForRoutinePrompt()
        }
    }

    private func refreshCatchUpModal() {
        let cards = CatchUpDeckBuilder.build(interventionService: interventionService)
        catchUpCards = cards
        catchUpCurrentSection = CatchUpDeckBuilder.currentSectionInfo()
        // Delay modal presentation to next runloop to ensure state propagates
        if !cards.isEmpty {
            DispatchQueue.main.async {
                showCatchUpModal = true
            }
        }
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
