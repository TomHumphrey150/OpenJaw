import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var mode: AppMode
    @Published private(set) var guidedStep: GuidedStep
    @Published private(set) var snapshot: DashboardSnapshot
    @Published private(set) var isProfileSheetPresented: Bool
    @Published private(set) var selectedExploreTab: ExploreTab
    @Published private(set) var exploreFeedback: String
    @Published private(set) var graphData: CausalGraphData
    @Published private(set) var graphDisplayFlags: GraphDisplayFlags
    @Published private(set) var focusedNodeID: String?
    @Published private(set) var graphSelectionText: String
    @Published private(set) var morningOutcomeSelection: MorningOutcomeSelection
    @Published var chatDraft: String

    private var experienceFlow: ExperienceFlow
    private var dailyCheckIns: [String: [String]]
    private var dailyDoseProgress: [String: [String: Double]]
    private var interventionCompletionEvents: [InterventionCompletionEvent]
    private var interventionDoseSettings: [String: DoseSettings]
    private var appleHealthConnections: [String: AppleHealthConnection]
    private var appleHealthValues: [String: Double]
    private var morningStates: [MorningState]
    private var activeInterventions: [String]
    private var inputCheckOperationToken: Int
    private var inputDoseOperationToken: Int
    private var inputDoseSettingsOperationToken: Int
    private var inputActiveOperationToken: Int
    private var appleHealthConnectionOperationToken: Int
    private var morningOutcomeOperationToken: Int
    private var graphDeactivationOperationToken: Int

    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private let persistUserDataPatch: @Sendable (UserDataPatch) async throws -> Bool
    private let appleHealthDoseService: AppleHealthDoseService
    private let nowProvider: () -> Date
    private static let maxCompletionEventsPerIntervention = 200

    convenience init(
        loadDashboardSnapshotUseCase: LoadDashboardSnapshotUseCase,
        accessibilityAnnouncer: AccessibilityAnnouncer
    ) {
        self.init(
            snapshot: loadDashboardSnapshotUseCase.execute(),
            graphData: CanonicalGraphLoader.loadGraphOrFallback(),
            initialExperienceFlow: .empty,
            initialDailyCheckIns: [:],
            initialDailyDoseProgress: [:],
            initialInterventionCompletionEvents: [],
            initialInterventionDoseSettings: [:],
            initialAppleHealthConnections: [:],
            initialMorningStates: [],
            initialActiveInterventions: [],
            persistUserDataPatch: { _ in true },
            appleHealthDoseService: MockAppleHealthDoseService(),
            accessibilityAnnouncer: accessibilityAnnouncer
        )
    }

    init(
        snapshot: DashboardSnapshot,
        graphData: CausalGraphData,
        initialExperienceFlow: ExperienceFlow = .empty,
        initialDailyCheckIns: [String: [String]] = [:],
        initialDailyDoseProgress: [String: [String: Double]] = [:],
        initialInterventionCompletionEvents: [InterventionCompletionEvent] = [],
        initialInterventionDoseSettings: [String: DoseSettings] = [:],
        initialAppleHealthConnections: [String: AppleHealthConnection] = [:],
        initialMorningStates: [MorningState] = [],
        initialActiveInterventions: [String] = [],
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true },
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        nowProvider: @escaping () -> Date = Date.init,
        accessibilityAnnouncer: AccessibilityAnnouncer
    ) {
        let todayKey = Self.localDateKey(from: nowProvider())

        mode = .explore
        guidedStep = .outcomes
        self.snapshot = snapshot
        isProfileSheetPresented = false
        selectedExploreTab = .inputs
        exploreFeedback = "AI chat backend is not connected yet."
        self.graphData = graphData
        graphDisplayFlags = GraphDisplayFlags(
            showFeedbackEdges: false,
            showProtectiveEdges: false,
            showInterventionNodes: false
        )
        focusedNodeID = Self.resolveNodeID(from: graphData, focusedNodeLabel: snapshot.situation.focusedNode)
        graphSelectionText = "Graph ready."
        morningOutcomeSelection = Self.morningOutcomeSelection(for: todayKey, from: initialMorningStates)
        chatDraft = ""

        experienceFlow = initialExperienceFlow
        dailyCheckIns = initialDailyCheckIns
        dailyDoseProgress = initialDailyDoseProgress
        let snapshotCompletionEvents = snapshot.inputs.flatMap { $0.completionEvents }
        interventionCompletionEvents = snapshotCompletionEvents.isEmpty
            ? initialInterventionCompletionEvents
            : snapshotCompletionEvents
        interventionDoseSettings = initialInterventionDoseSettings
        appleHealthConnections = initialAppleHealthConnections
        appleHealthValues = [:]
        morningStates = initialMorningStates
        let snapshotActiveInterventions = snapshot.inputs.compactMap { input -> String? in
            input.isActive ? input.id : nil
        }
        activeInterventions = snapshotActiveInterventions.isEmpty ? initialActiveInterventions : snapshotActiveInterventions

        inputCheckOperationToken = 0
        inputDoseOperationToken = 0
        inputDoseSettingsOperationToken = 0
        inputActiveOperationToken = 0
        appleHealthConnectionOperationToken = 0
        morningOutcomeOperationToken = 0
        graphDeactivationOperationToken = 0

        self.persistUserDataPatch = persistUserDataPatch
        self.appleHealthDoseService = appleHealthDoseService
        self.nowProvider = nowProvider
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func openProfileSheet() {
        isProfileSheetPresented = true
    }

    var morningStateHistory: [MorningState] {
        morningStates
    }

    func setProfileSheetPresented(_ isPresented: Bool) {
        isProfileSheetPresented = isPresented
    }

    func advanceFromOutcomes() {
        transitionToGuidedStep(.situation, requires: .outcomes)
    }

    func advanceFromSituation() {
        transitionToGuidedStep(.inputs, requires: .situation)
    }

    func completeGuidedFlow() {
        guard mode == .guided else { return }
        guard guidedStep == .inputs else { return }
        mode = .explore
        selectedExploreTab = .inputs
        markGuidedCompleted(on: Self.localDateKey(from: nowProvider()))
        announce("Guided flow complete. Explore mode unlocked.")
    }

    func selectExploreTab(_ tab: ExploreTab) {
        guard mode == .explore else { return }
        selectedExploreTab = tab
        announce("\(tab.title) tab selected.")
    }

    func performExploreAction(_ action: ExploreContextAction) {
        guard mode == .explore else { return }
        exploreFeedback = action.detail
        announce(action.announcement)
    }

    func submitChatPrompt() {
        guard mode == .explore else { return }
        let prompt = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            exploreFeedback = "Enter a request before sending."
            announce(exploreFeedback)
            return
        }
        exploreFeedback = "AI chat backend is not connected yet. Draft not sent: \(prompt)"
        chatDraft = ""
        announce("AI chat backend is not connected yet.")
    }

    func setShowInterventionNodes(_ isEnabled: Bool) {
        guard graphDisplayFlags.showInterventionNodes != isEnabled else { return }
        graphDisplayFlags = GraphDisplayFlags(
            showFeedbackEdges: graphDisplayFlags.showFeedbackEdges,
            showProtectiveEdges: graphDisplayFlags.showProtectiveEdges,
            showInterventionNodes: isEnabled
        )
    }

    func setShowFeedbackEdges(_ isEnabled: Bool) {
        guard graphDisplayFlags.showFeedbackEdges != isEnabled else { return }
        graphDisplayFlags = GraphDisplayFlags(
            showFeedbackEdges: isEnabled,
            showProtectiveEdges: graphDisplayFlags.showProtectiveEdges,
            showInterventionNodes: graphDisplayFlags.showInterventionNodes
        )
    }

    func setShowProtectiveEdges(_ isEnabled: Bool) {
        guard graphDisplayFlags.showProtectiveEdges != isEnabled else { return }
        graphDisplayFlags = GraphDisplayFlags(
            showFeedbackEdges: graphDisplayFlags.showFeedbackEdges,
            showProtectiveEdges: isEnabled,
            showInterventionNodes: graphDisplayFlags.showInterventionNodes
        )
    }

    func toggleGraphNodeDeactivated(_ nodeID: String) {
        guard mode == .explore else { return }
        guard let nodeIndex = graphData.nodes.firstIndex(where: { $0.data.id == nodeID }) else { return }

        let previousGraphData = graphData
        let currentNode = graphData.nodes[nodeIndex].data
        let nextIsDeactivated = !(currentNode.isDeactivated ?? false)

        var nextNodes = graphData.nodes
        nextNodes[nodeIndex] = GraphNodeElement(
            data: GraphNodeData(
                id: currentNode.id,
                label: currentNode.label,
                styleClass: currentNode.styleClass,
                confirmed: currentNode.confirmed,
                tier: currentNode.tier,
                tooltip: currentNode.tooltip,
                isDeactivated: nextIsDeactivated
            )
        )

        let nextGraphData = CausalGraphData(
            nodes: nextNodes,
            edges: graphData.edges
        )
        graphData = nextGraphData

        let nodeLabel = Self.firstLine(for: currentNode.label)
        let successMessage = nextIsDeactivated
            ? "\(nodeLabel) deactivated."
            : "\(nodeLabel) reactivated."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextGraphDeactivationOperationToken()
        Task {
            do {
                try await persistPatch(graphDeactivationPatch(for: nextGraphData))
            } catch {
                guard operationToken == graphDeactivationOperationToken else { return }
                graphData = previousGraphData
                let failureMessage = "Could not save \(nodeLabel) state. Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func toggleGraphEdgeDeactivated(
        sourceID: String,
        targetID: String,
        label: String?,
        edgeType: String?
    ) {
        guard mode == .explore else { return }
        guard let edgeIndex = graphData.edges.firstIndex(where: {
            Self.edgeIdentityMatches(
                edgeData: $0.data,
                sourceID: sourceID,
                targetID: targetID,
                label: label,
                edgeType: edgeType
            )
        }) else { return }

        let previousGraphData = graphData
        let currentEdge = graphData.edges[edgeIndex].data
        let nextIsDeactivated = !(currentEdge.isDeactivated ?? false)

        var nextEdges = graphData.edges
        nextEdges[edgeIndex] = GraphEdgeElement(
            data: GraphEdgeData(
                source: currentEdge.source,
                target: currentEdge.target,
                label: currentEdge.label,
                edgeType: currentEdge.edgeType,
                edgeColor: currentEdge.edgeColor,
                tooltip: currentEdge.tooltip,
                isDeactivated: nextIsDeactivated
            )
        )

        let nextGraphData = CausalGraphData(
            nodes: graphData.nodes,
            edges: nextEdges
        )
        graphData = nextGraphData

        let edgeText = edgeDescription(sourceID: sourceID, targetID: targetID)
        let successMessage = nextIsDeactivated
            ? "Link \(edgeText) deactivated."
            : "Link \(edgeText) reactivated."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextGraphDeactivationOperationToken()
        Task {
            do {
                try await persistPatch(graphDeactivationPatch(for: nextGraphData))
            } catch {
                guard operationToken == graphDeactivationOperationToken else { return }
                graphData = previousGraphData
                let failureMessage = "Could not save link \(edgeText) state. Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func toggleInputCheckedToday(_ inputID: String) {
        guard mode == .explore else { return }
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }

        let currentInput = snapshot.inputs[index]
        guard currentInput.trackingMode == .binary else { return }
        let previousSnapshot = snapshot
        let previousDailyCheckIns = dailyCheckIns
        let previousInterventionCompletionEvents = interventionCompletionEvents

        let currentDayCount = dayCount(for: currentInput)
        let nextCheckedToday = !currentInput.isCheckedToday
        let nextDayCount = updatedDayCount(
            currentDayCount: currentDayCount,
            currentlyCheckedToday: currentInput.isCheckedToday
        )
        let nextStatusText = statusText(
            dayCount: nextDayCount,
            checkedToday: nextCheckedToday
        )

        let eventTimestamp = Self.timestamp(from: nowProvider())
        let nextInterventionCompletionEvents: [InterventionCompletionEvent]
        if nextCheckedToday {
            nextInterventionCompletionEvents = Self.appendCompletionEvent(
                InterventionCompletionEvent(
                    interventionId: currentInput.id,
                    occurredAt: eventTimestamp,
                    source: .binaryCheck
                ),
                to: interventionCompletionEvents,
                maxPerIntervention: Self.maxCompletionEventsPerIntervention
            )
        } else {
            nextInterventionCompletionEvents = interventionCompletionEvents
        }

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .binary,
            statusText: nextStatusText,
            completion: Double(nextDayCount) / 7.0,
            isCheckedToday: nextCheckedToday,
            doseState: nil,
            completionEvents: Self.completionEvents(
                for: currentInput.id,
                in: nextInterventionCompletionEvents
            ),
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState
        )

        let dateKey = Self.localDateKey(from: nowProvider())
        let nextDailyCheckIns = Self.updatedDailyCheckIns(
            from: dailyCheckIns,
            dateKey: dateKey,
            interventionID: currentInput.id,
            isChecked: nextCheckedToday
        )

        updateInput(nextInput, at: index)
        dailyCheckIns = nextDailyCheckIns
        interventionCompletionEvents = nextInterventionCompletionEvents

        let successMessage = nextCheckedToday
            ? "\(currentInput.name) checked for today."
            : "\(currentInput.name) unchecked for today."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextInputCheckOperationToken()
        Task {
            do {
                try await persistPatch(
                    .dailyCheckInsAndCompletionEvents(
                        nextDailyCheckIns,
                        nextInterventionCompletionEvents
                    )
                )
            } catch {
                guard operationToken == inputCheckOperationToken else { return }
                dailyCheckIns = previousDailyCheckIns
                interventionCompletionEvents = previousInterventionCompletionEvents
                snapshot = previousSnapshot
                let failureMessage = "Could not save \(currentInput.name) check-in. Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func incrementInputDose(_ inputID: String) {
        guard mode == .explore else { return }
        updateDose(inputID: inputID, operation: .increment)
    }

    func decrementInputDose(_ inputID: String) {
        guard mode == .explore else { return }
        updateDose(inputID: inputID, operation: .decrement)
    }

    func resetInputDose(_ inputID: String) {
        guard mode == .explore else { return }
        updateDose(inputID: inputID, operation: .reset)
    }

    func connectInputToAppleHealth(_ inputID: String) {
        guard mode == .explore else { return }
        guard appleHealthDoseService.isHealthDataAvailable() else {
            let message = "Apple Health is unavailable on this device."
            exploreFeedback = message
            announce(message)
            return
        }

        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }
        let currentInput = snapshot.inputs[index]
        guard let currentDoseState = currentInput.doseState else { return }
        guard let currentAppleHealthState = currentInput.appleHealthState else { return }
        guard currentAppleHealthState.available else { return }
        guard let config = currentAppleHealthState.config else { return }

        let previousSnapshot = snapshot
        let previousConnections = appleHealthConnections
        let timestamp = Self.timestampNow()
        let connection = AppleHealthConnection(
            isConnected: true,
            connectedAt: appleHealthConnections[inputID]?.connectedAt ?? timestamp,
            lastSyncAt: nil,
            lastSyncStatus: .connecting,
            lastErrorCode: nil
        )

        appleHealthConnections[inputID] = connection
        let nextState = InputAppleHealthState(
            available: true,
            connected: true,
            syncStatus: .connecting,
            todayHealthValue: appleHealthValues[inputID],
            lastSyncAt: connection.lastSyncAt,
            config: config
        )
        let nextInput = doseInput(
            from: currentInput,
            manualValue: currentDoseState.manualValue,
            goal: currentDoseState.goal,
            increment: currentDoseState.increment,
            unit: currentDoseState.unit,
            healthValue: appleHealthValues[inputID],
            appleHealthState: nextState
        )
        updateInput(nextInput, at: index)

        let operationToken = nextAppleHealthConnectionOperationToken()
        Task {
            do {
                try await appleHealthDoseService.requestReadAuthorization(for: [config])
                try await persistPatch(.appleHealthConnections(appleHealthConnections))
                guard operationToken == appleHealthConnectionOperationToken else { return }
                let message = "Connected \(currentInput.name) to Apple Health."
                exploreFeedback = message
                announce(message)
                await refreshAppleHealth(for: inputID)
            } catch {
                guard operationToken == appleHealthConnectionOperationToken else { return }
                appleHealthConnections = previousConnections
                snapshot = previousSnapshot
                let message = "Could not connect \(currentInput.name) to Apple Health. Reverted."
                exploreFeedback = message
                announce(message)
            }
        }
    }

    func disconnectInputFromAppleHealth(_ inputID: String) {
        guard mode == .explore else { return }
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }
        let currentInput = snapshot.inputs[index]
        guard let currentDoseState = currentInput.doseState else { return }
        guard let currentAppleHealthState = currentInput.appleHealthState else { return }
        guard let config = currentAppleHealthState.config else { return }

        let previousSnapshot = snapshot
        let previousConnections = appleHealthConnections
        let previousHealthValues = appleHealthValues

        appleHealthConnections.removeValue(forKey: inputID)
        appleHealthValues.removeValue(forKey: inputID)

        let nextState = InputAppleHealthState(
            available: true,
            connected: false,
            syncStatus: .disconnected,
            todayHealthValue: nil,
            lastSyncAt: nil,
            config: config
        )
        let nextInput = doseInput(
            from: currentInput,
            manualValue: currentDoseState.manualValue,
            goal: currentDoseState.goal,
            increment: currentDoseState.increment,
            unit: currentDoseState.unit,
            healthValue: nil,
            appleHealthState: nextState
        )
        updateInput(nextInput, at: index)

        let operationToken = nextAppleHealthConnectionOperationToken()
        Task {
            do {
                try await persistPatch(.appleHealthConnections(appleHealthConnections))
                guard operationToken == appleHealthConnectionOperationToken else { return }
                let message = "Disconnected \(currentInput.name) from Apple Health."
                exploreFeedback = message
                announce(message)
            } catch {
                guard operationToken == appleHealthConnectionOperationToken else { return }
                appleHealthConnections = previousConnections
                appleHealthValues = previousHealthValues
                snapshot = previousSnapshot
                let message = "Could not disconnect \(currentInput.name) from Apple Health. Reverted."
                exploreFeedback = message
                announce(message)
            }
        }
    }

    func refreshAppleHealth(for inputID: String) async {
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }
        let currentInput = snapshot.inputs[index]
        guard let currentDoseState = currentInput.doseState else { return }
        guard let currentAppleHealthState = currentInput.appleHealthState else { return }
        guard currentAppleHealthState.connected else { return }
        guard let config = currentAppleHealthState.config else { return }

        let syncingState = InputAppleHealthState(
            available: true,
            connected: true,
            syncStatus: .syncing,
            todayHealthValue: appleHealthValues[inputID],
            lastSyncAt: currentAppleHealthState.lastSyncAt,
            config: config
        )
        let syncingInput = doseInput(
            from: currentInput,
            manualValue: currentDoseState.manualValue,
            goal: currentDoseState.goal,
            increment: currentDoseState.increment,
            unit: currentDoseState.unit,
            healthValue: appleHealthValues[inputID],
            appleHealthState: syncingState
        )
        updateInput(syncingInput, at: index)

        do {
            let healthValue = try await appleHealthDoseService.fetchTodayValue(
                for: config,
                unit: currentDoseState.unit,
                now: nowProvider()
            )
            if let healthValue {
                appleHealthValues[inputID] = max(0, healthValue)
            } else {
                appleHealthValues.removeValue(forKey: inputID)
            }

            let status: AppleHealthSyncStatus = healthValue == nil ? .noData : .synced
            let syncTimestamp = Self.timestampNow()
            let updatedConnection = AppleHealthConnection(
                isConnected: true,
                connectedAt: appleHealthConnections[inputID]?.connectedAt ?? syncTimestamp,
                lastSyncAt: syncTimestamp,
                lastSyncStatus: status,
                lastErrorCode: nil
            )
            appleHealthConnections[inputID] = updatedConnection

            if let refreshedIndex = snapshot.inputs.firstIndex(where: { $0.id == inputID }) {
                let refreshedInput = snapshot.inputs[refreshedIndex]
                if let refreshedDoseState = refreshedInput.doseState {
                    let nextAppleHealthState = InputAppleHealthState(
                        available: true,
                        connected: true,
                        syncStatus: status,
                        todayHealthValue: appleHealthValues[inputID],
                        lastSyncAt: syncTimestamp,
                        config: config
                    )
                    let nextInput = doseInput(
                        from: refreshedInput,
                        manualValue: refreshedDoseState.manualValue,
                        goal: refreshedDoseState.goal,
                        increment: refreshedDoseState.increment,
                        unit: refreshedDoseState.unit,
                        healthValue: appleHealthValues[inputID],
                        appleHealthState: nextAppleHealthState
                    )
                    updateInput(nextInput, at: refreshedIndex)
                }
            }

            try await persistPatch(.appleHealthConnections(appleHealthConnections))

            let message = healthValue == nil
                ? "No Apple Health data for \(currentInput.name) today. Using app entries."
                : "Synced \(currentInput.name) from Apple Health."
            exploreFeedback = message
            announce(message)
        } catch {
            let syncTimestamp = Self.timestampNow()
            let updatedConnection = AppleHealthConnection(
                isConnected: true,
                connectedAt: appleHealthConnections[inputID]?.connectedAt ?? syncTimestamp,
                lastSyncAt: syncTimestamp,
                lastSyncStatus: .failed,
                lastErrorCode: Self.appleHealthErrorCode(for: error)
            )
            appleHealthConnections[inputID] = updatedConnection

            if let refreshedIndex = snapshot.inputs.firstIndex(where: { $0.id == inputID }) {
                let refreshedInput = snapshot.inputs[refreshedIndex]
                if let refreshedDoseState = refreshedInput.doseState {
                    let failedState = InputAppleHealthState(
                        available: true,
                        connected: true,
                        syncStatus: .failed,
                        todayHealthValue: appleHealthValues[inputID],
                        lastSyncAt: syncTimestamp,
                        config: config
                    )
                    let failedInput = doseInput(
                        from: refreshedInput,
                        manualValue: refreshedDoseState.manualValue,
                        goal: refreshedDoseState.goal,
                        increment: refreshedDoseState.increment,
                        unit: refreshedDoseState.unit,
                        healthValue: appleHealthValues[inputID],
                        appleHealthState: failedState
                    )
                    updateInput(failedInput, at: refreshedIndex)
                }
            }

            let message = "Could not refresh Apple Health for \(currentInput.name)."
            exploreFeedback = message
            announce(message)
            try? await persistPatch(.appleHealthConnections(appleHealthConnections))
        }
    }

    func refreshAllConnectedAppleHealth() async {
        let connectedInputs = snapshot.inputs.compactMap { input -> String? in
            guard input.appleHealthState?.connected == true else {
                return nil
            }
            return input.id
        }

        for inputID in connectedInputs {
            await refreshAppleHealth(for: inputID)
        }
    }

    func updateDoseSettings(_ inputID: String, dailyGoal: Double, increment: Double) {
        guard mode == .explore else { return }
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }

        let currentInput = snapshot.inputs[index]
        guard currentInput.trackingMode == .dose else { return }
        guard let currentDoseState = currentInput.doseState else { return }

        let safeGoal = max(1, dailyGoal)
        let safeIncrement = max(1, increment)
        let previousSnapshot = snapshot
        let previousSettings = interventionDoseSettings

        let nextState = InputDoseState(
            manualValue: currentDoseState.manualValue,
            healthValue: currentDoseState.healthValue,
            goal: safeGoal,
            increment: safeIncrement,
            unit: currentDoseState.unit
        )
        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .dose,
            statusText: doseStatusText(for: nextState),
            completion: nextState.completionClamped,
            isCheckedToday: nextState.isGoalMet,
            doseState: nextState,
            completionEvents: currentInput.completionEvents,
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState
        )

        var nextSettings = interventionDoseSettings
        nextSettings[inputID] = DoseSettings(dailyGoal: safeGoal, increment: safeIncrement)

        updateInput(nextInput, at: index)
        interventionDoseSettings = nextSettings

        let successMessage = "Saved dose settings for \(currentInput.name)."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextInputDoseSettingsOperationToken()
        Task {
            do {
                try await persistPatch(.interventionDoseSettings(nextSettings))
            } catch {
                guard operationToken == inputDoseSettingsOperationToken else { return }
                interventionDoseSettings = previousSettings
                snapshot = previousSnapshot
                let failureMessage = "Could not save dose settings for \(currentInput.name). Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func toggleInputActive(_ inputID: String) {
        guard mode == .explore else { return }
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }

        let currentInput = snapshot.inputs[index]
        let previousSnapshot = snapshot
        let previousActiveInterventions = activeInterventions
        let nextActive = !currentInput.isActive

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: currentInput.trackingMode,
            statusText: currentInput.statusText,
            completion: currentInput.completion,
            isCheckedToday: currentInput.isCheckedToday,
            doseState: currentInput.doseState,
            completionEvents: currentInput.completionEvents,
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: nextActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState
        )

        let currentActiveInterventions = snapshot.inputs.compactMap { input -> String? in
            input.isActive ? input.id : nil
        }
        let nextActiveInterventions = Self.updatedActiveInterventions(
            from: currentActiveInterventions,
            interventionID: currentInput.id,
            isActive: nextActive
        )

        updateInput(nextInput, at: index)
        activeInterventions = nextActiveInterventions

        let successMessage = nextActive
            ? "\(currentInput.name) started tracking."
            : "\(currentInput.name) stopped tracking."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextInputActiveOperationToken()
        Task {
            do {
                try await persistPatch(.activeInterventions(nextActiveInterventions))
            } catch {
                guard operationToken == inputActiveOperationToken else { return }
                activeInterventions = previousActiveInterventions
                snapshot = previousSnapshot
                let failureMessage = "Could not save tracking state for \(currentInput.name). Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func setMorningOutcomeValue(_ value: Int?, for field: MorningOutcomeField) {
        guard mode == .explore else { return }

        let clampedValue = value.map { max(0, min(10, $0)) }
        let nextSelection = morningOutcomeSelection.updating(field: field, value: clampedValue)
        guard nextSelection != morningOutcomeSelection else { return }

        let previousSelection = morningOutcomeSelection
        let previousMorningStates = morningStates
        let nextRecord = nextSelection.asMorningState(createdAt: Self.timestampNow())
        let nextMorningStates = Self.upsert(morningState: nextRecord, in: morningStates)

        morningOutcomeSelection = nextSelection
        morningStates = nextMorningStates

        let successMessage = "Saved morning outcomes for \(nextSelection.nightID)."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextMorningOutcomeOperationToken()
        Task {
            do {
                try await persistPatch(.morningStates(nextMorningStates))
            } catch {
                guard operationToken == morningOutcomeOperationToken else { return }
                morningOutcomeSelection = previousSelection
                morningStates = previousMorningStates
                let failureMessage = "Could not save morning outcomes. Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func handleAppMovedToBackground() {
        guard mode == .guided else { return }
        guard experienceFlow.lastGuidedStatus == .inProgress else { return }
        markGuidedInterrupted(on: Self.localDateKey(from: nowProvider()))
    }

    func handleGraphEvent(_ event: GraphEvent) {
        switch event {
        case .graphReady:
            graphSelectionText = "Graph ready."
        case .nodeSelected(let id, let label):
            focusedNodeID = id
            graphSelectionText = "Selected node: \(label)."
            updateFocusedNode(label)
            announce(graphSelectionText)
        case .edgeSelected(_, _, let sourceLabel, let targetLabel, _, _):
            graphSelectionText = "Selected link: \(sourceLabel) to \(targetLabel)."
            announce(graphSelectionText)
        case .viewportChanged(let zoom):
            graphSelectionText = "Graph zoom \(String(format: "%.2f", zoom))."
        case .renderError(let message):
            graphSelectionText = "Graph render error: \(message)"
            announce(graphSelectionText)
        }
    }

    private func transitionToGuidedStep(_ nextStep: GuidedStep, requires expectedStep: GuidedStep) {
        guard mode == .guided else { return }
        guard guidedStep == expectedStep else { return }
        guidedStep = nextStep
        announce(nextStep.announcement)
    }

    private func announce(_ message: String) {
        accessibilityAnnouncer.announce(message)
    }

    private func updateInput(_ nextInput: InputStatus, at index: Int) {
        var inputs = snapshot.inputs
        inputs[index] = nextInput
        snapshot = DashboardSnapshot(
            outcomes: snapshot.outcomes,
            outcomeRecords: snapshot.outcomeRecords,
            outcomesMetadata: snapshot.outcomesMetadata,
            situation: snapshot.situation,
            inputs: inputs
        )
    }

    private func updateFocusedNode(_ label: String) {
        snapshot = DashboardSnapshot(
            outcomes: snapshot.outcomes,
            outcomeRecords: snapshot.outcomeRecords,
            outcomesMetadata: snapshot.outcomesMetadata,
            situation: SituationSummary(
                focusedNode: label,
                tier: snapshot.situation.tier,
                visibleHotspots: snapshot.situation.visibleHotspots,
                topSource: snapshot.situation.topSource
            ),
            inputs: snapshot.inputs
        )
    }

    private func markGuidedEntry(on dateKey: String) {
        persistExperienceFlow(
            ExperienceFlow(
                hasCompletedInitialGuidedFlow: experienceFlow.hasCompletedInitialGuidedFlow,
                lastGuidedEntryDate: dateKey,
                lastGuidedCompletedDate: experienceFlow.lastGuidedCompletedDate,
                lastGuidedStatus: .inProgress
            )
        )
    }

    private func markGuidedCompleted(on dateKey: String) {
        persistExperienceFlow(
            ExperienceFlow(
                hasCompletedInitialGuidedFlow: true,
                lastGuidedEntryDate: dateKey,
                lastGuidedCompletedDate: dateKey,
                lastGuidedStatus: .completed
            )
        )
    }

    private func markGuidedInterrupted(on dateKey: String) {
        let entryDate = experienceFlow.lastGuidedEntryDate ?? dateKey
        persistExperienceFlow(
            ExperienceFlow(
                hasCompletedInitialGuidedFlow: experienceFlow.hasCompletedInitialGuidedFlow,
                lastGuidedEntryDate: entryDate,
                lastGuidedCompletedDate: experienceFlow.lastGuidedCompletedDate,
                lastGuidedStatus: .interrupted
            )
        )
    }

    private func persistExperienceFlow(_ next: ExperienceFlow) {
        guard next != experienceFlow else { return }
        experienceFlow = next
        Task {
            do {
                try await persistPatch(.experienceFlow(next))
            } catch {
            }
        }
    }

    private func persistPatch(_ patch: UserDataPatch) async throws {
        let didWrite = try await persistUserDataPatch(patch)
        guard didWrite else {
            throw PersistenceError.writeRejected
        }
    }

    private func nextInputCheckOperationToken() -> Int {
        inputCheckOperationToken += 1
        return inputCheckOperationToken
    }

    private func nextInputDoseOperationToken() -> Int {
        inputDoseOperationToken += 1
        return inputDoseOperationToken
    }

    private func nextInputDoseSettingsOperationToken() -> Int {
        inputDoseSettingsOperationToken += 1
        return inputDoseSettingsOperationToken
    }

    private func nextInputActiveOperationToken() -> Int {
        inputActiveOperationToken += 1
        return inputActiveOperationToken
    }

    private func nextAppleHealthConnectionOperationToken() -> Int {
        appleHealthConnectionOperationToken += 1
        return appleHealthConnectionOperationToken
    }

    private func nextMorningOutcomeOperationToken() -> Int {
        morningOutcomeOperationToken += 1
        return morningOutcomeOperationToken
    }

    private func nextGraphDeactivationOperationToken() -> Int {
        graphDeactivationOperationToken += 1
        return graphDeactivationOperationToken
    }

    private func dayCount(for input: InputStatus) -> Int {
        let scaled = (input.completion * 7.0).rounded()
        return max(0, min(7, Int(scaled)))
    }

    private func updatedDayCount(currentDayCount: Int, currentlyCheckedToday: Bool) -> Int {
        if currentlyCheckedToday {
            return max(0, currentDayCount - 1)
        }

        return min(7, currentDayCount + 1)
    }

    private func statusText(dayCount: Int, checkedToday: Bool) -> String {
        if checkedToday {
            return "Checked today"
        }

        if dayCount > 0 {
            return "\(dayCount)/7 days"
        }

        return "Not checked yet"
    }

    private func updateDose(inputID: String, operation: DoseOperation) {
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }

        let currentInput = snapshot.inputs[index]
        guard currentInput.trackingMode == .dose else { return }
        guard let doseState = currentInput.doseState else { return }

        let previousSnapshot = snapshot
        let previousDailyDoseProgress = dailyDoseProgress
        let previousInterventionCompletionEvents = interventionCompletionEvents

        let nextValue: Double
        switch operation {
        case .increment:
            nextValue = doseState.manualValue + doseState.increment
        case .decrement:
            nextValue = max(0, doseState.manualValue - doseState.increment)
        case .reset:
            nextValue = 0
        }

        let nextDoseState = InputDoseState(
            manualValue: nextValue,
            healthValue: doseState.healthValue,
            goal: doseState.goal,
            increment: doseState.increment,
            unit: doseState.unit
        )

        let eventTimestamp = Self.timestamp(from: nowProvider())
        let nextInterventionCompletionEvents: [InterventionCompletionEvent]
        if operation == .increment {
            nextInterventionCompletionEvents = Self.appendCompletionEvent(
                InterventionCompletionEvent(
                    interventionId: currentInput.id,
                    occurredAt: eventTimestamp,
                    source: .doseIncrement
                ),
                to: interventionCompletionEvents,
                maxPerIntervention: Self.maxCompletionEventsPerIntervention
            )
        } else {
            nextInterventionCompletionEvents = interventionCompletionEvents
        }

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .dose,
            statusText: doseStatusText(for: nextDoseState),
            completion: nextDoseState.completionClamped,
            isCheckedToday: nextDoseState.isGoalMet,
            doseState: nextDoseState,
            completionEvents: Self.completionEvents(
                for: currentInput.id,
                in: nextInterventionCompletionEvents
            ),
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState
        )

        let dateKey = Self.localDateKey(from: nowProvider())
        let nextDailyDoseProgress = Self.updatedDailyDoseProgress(
            from: dailyDoseProgress,
            dateKey: dateKey,
            interventionID: currentInput.id,
            value: nextValue
        )

        updateInput(nextInput, at: index)
        dailyDoseProgress = nextDailyDoseProgress
        interventionCompletionEvents = nextInterventionCompletionEvents

        let successMessage: String
        switch operation {
        case .increment:
            successMessage = "\(currentInput.name) progress increased."
        case .decrement:
            successMessage = "\(currentInput.name) progress decreased."
        case .reset:
            successMessage = "\(currentInput.name) progress reset."
        }

        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextInputDoseOperationToken()
        Task {
            do {
                try await persistPatch(
                    .dailyDoseProgressAndCompletionEvents(
                        nextDailyDoseProgress,
                        nextInterventionCompletionEvents
                    )
                )
            } catch {
                guard operationToken == inputDoseOperationToken else { return }
                dailyDoseProgress = previousDailyDoseProgress
                interventionCompletionEvents = previousInterventionCompletionEvents
                snapshot = previousSnapshot
                let failureMessage = "Could not save dose progress for \(currentInput.name). Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    private func doseStatusText(for state: InputDoseState) -> String {
        let percent = Int((state.completionRaw * 100).rounded())
        return "\(formattedDoseValue(state.value))/\(formattedDoseValue(state.goal)) \(state.unit.displayName) today (\(percent)%)"
    }

    private func doseInput(
        from currentInput: InputStatus,
        manualValue: Double,
        goal: Double,
        increment: Double,
        unit: DoseUnit,
        healthValue: Double?,
        appleHealthState: InputAppleHealthState?
    ) -> InputStatus {
        let nextDoseState = InputDoseState(
            manualValue: manualValue,
            healthValue: healthValue,
            goal: goal,
            increment: increment,
            unit: unit
        )

        return InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .dose,
            statusText: doseStatusText(for: nextDoseState),
            completion: nextDoseState.completionClamped,
            isCheckedToday: nextDoseState.isGoalMet,
            doseState: nextDoseState,
            completionEvents: currentInput.completionEvents,
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: appleHealthState
        )
    }

    private func formattedDoseValue(_ value: Double) -> String {
        let roundedValue = value.rounded()
        if abs(roundedValue - value) < 0.0001 {
            return String(Int(roundedValue))
        }

        return String(format: "%.1f", value)
    }

    private func graphDeactivationPatch(for graphData: CausalGraphData) -> UserDataPatch {
        UserDataPatch.customCausalDiagram(
            CustomCausalDiagram(
                graphData: graphData,
                lastModified: Self.timestamp(from: nowProvider())
            )
        )
    }

    private func edgeDescription(sourceID: String, targetID: String) -> String {
        let labelsByID = Dictionary(
            uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, Self.firstLine(for: $0.data.label)) }
        )
        let sourceLabel = labelsByID[sourceID] ?? sourceID
        let targetLabel = labelsByID[targetID] ?? targetID
        return "\(sourceLabel) to \(targetLabel)"
    }

    private static func updatedDailyCheckIns(
        from current: [String: [String]],
        dateKey: String,
        interventionID: String,
        isChecked: Bool
    ) -> [String: [String]] {
        var next = current
        var interventionIDs = next[dateKey] ?? []

        if isChecked {
            if !interventionIDs.contains(interventionID) {
                interventionIDs.append(interventionID)
            }
        } else {
            interventionIDs.removeAll { $0 == interventionID }
        }

        next[dateKey] = interventionIDs
        return next
    }

    private static func updatedDailyDoseProgress(
        from current: [String: [String: Double]],
        dateKey: String,
        interventionID: String,
        value: Double
    ) -> [String: [String: Double]] {
        var next = current
        var progress = next[dateKey] ?? [:]

        if value <= 0 {
            progress.removeValue(forKey: interventionID)
        } else {
            progress[interventionID] = value
        }

        next[dateKey] = progress
        return next
    }

    private static func completionEvents(
        for interventionID: String,
        in events: [InterventionCompletionEvent]
    ) -> [InterventionCompletionEvent] {
        events
            .filter { $0.interventionId == interventionID }
            .sorted { lhs, rhs in
                lhs.occurredAt > rhs.occurredAt
            }
    }

    private static func appendCompletionEvent(
        _ event: InterventionCompletionEvent,
        to current: [InterventionCompletionEvent],
        maxPerIntervention: Int
    ) -> [InterventionCompletionEvent] {
        var next = current
        next.append(event)

        let matchingIndices = next.indices.filter { index in
            next[index].interventionId == event.interventionId
        }
        let overflowCount = matchingIndices.count - maxPerIntervention
        if overflowCount <= 0 {
            return next
        }

        let oldestIndices = matchingIndices
            .sorted { lhs, rhs in
                if next[lhs].occurredAt == next[rhs].occurredAt {
                    return lhs < rhs
                }
                return next[lhs].occurredAt < next[rhs].occurredAt
            }
            .prefix(overflowCount)
            .sorted(by: >)

        for index in oldestIndices {
            next.remove(at: index)
        }

        return next
    }

    private static func updatedActiveInterventions(
        from current: [String],
        interventionID: String,
        isActive: Bool
    ) -> [String] {
        var deduped: [String] = []
        var seen = Set<String>()

        for id in current {
            if id.isEmpty {
                continue
            }
            if seen.insert(id).inserted {
                deduped.append(id)
            }
        }

        deduped.removeAll { $0 == interventionID }
        if isActive {
            deduped.append(interventionID)
        }

        return deduped
    }

    private static func resolveNodeID(from graphData: CausalGraphData, focusedNodeLabel: String) -> String? {
        graphData.nodes.first {
            firstLine(for: $0.data.label) == focusedNodeLabel
        }?.data.id
    }

    private static func edgeIdentityMatches(
        edgeData: GraphEdgeData,
        sourceID: String,
        targetID: String,
        label: String?,
        edgeType: String?
    ) -> Bool {
        guard edgeData.source == sourceID else { return false }
        guard edgeData.target == targetID else { return false }
        guard normalizedOptionalString(edgeData.label) == normalizedOptionalString(label) else { return false }
        return normalizedOptionalString(edgeData.edgeType) == normalizedOptionalString(edgeType)
    }

    private static func firstLine(for label: String) -> String {
        label.components(separatedBy: "\n").first ?? label
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func localDateKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func morningOutcomeSelection(for dateKey: String, from morningStates: [MorningState]) -> MorningOutcomeSelection {
        guard let state = morningStates.first(where: { $0.nightId == dateKey }) else {
            return MorningOutcomeSelection.empty(nightID: dateKey)
        }

        return MorningOutcomeSelection(
            nightID: dateKey,
            globalSensation: state.globalSensation.map { Int($0.rounded()) },
            neckTightness: state.neckTightness.map { Int($0.rounded()) },
            jawSoreness: state.jawSoreness.map { Int($0.rounded()) },
            earFullness: state.earFullness.map { Int($0.rounded()) },
            healthAnxiety: state.healthAnxiety.map { Int($0.rounded()) },
            stressLevel: state.stressLevel.map { Int($0.rounded()) }
        )
    }

    private static func upsert(morningState: MorningState, in existingStates: [MorningState]) -> [MorningState] {
        var mutableStates = existingStates
        guard let existingIndex = mutableStates.firstIndex(where: { $0.nightId == morningState.nightId }) else {
            mutableStates.append(morningState)
            return mutableStates
        }

        let existingCreatedAt = mutableStates[existingIndex].createdAt
        mutableStates[existingIndex] = MorningState(
            nightId: morningState.nightId,
            globalSensation: morningState.globalSensation,
            neckTightness: morningState.neckTightness,
            jawSoreness: morningState.jawSoreness,
            earFullness: morningState.earFullness,
            healthAnxiety: morningState.healthAnxiety,
            stressLevel: morningState.stressLevel,
            createdAt: existingCreatedAt
        )
        return mutableStates
    }

    private static func timestampNow() -> String {
        timestamp(from: Date())
    }

    private static func timestamp(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func appleHealthErrorCode(for error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}

private enum PersistenceError: Error {
    case writeRejected
}

private enum DoseOperation {
    case increment
    case decrement
    case reset
}
