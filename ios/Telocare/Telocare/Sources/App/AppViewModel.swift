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
    private var morningStates: [MorningState]
    private var hiddenInterventions: [String]
    private var inputCheckOperationToken: Int
    private var inputHiddenOperationToken: Int
    private var morningOutcomeOperationToken: Int

    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private let persistUserDataPatch: @Sendable (UserDataPatch) async throws -> Bool
    private let nowProvider: () -> Date

    convenience init(
        loadDashboardSnapshotUseCase: LoadDashboardSnapshotUseCase,
        accessibilityAnnouncer: AccessibilityAnnouncer
    ) {
        self.init(
            snapshot: loadDashboardSnapshotUseCase.execute(),
            graphData: CanonicalGraphLoader.loadGraphOrFallback(),
            initialExperienceFlow: .empty,
            initialDailyCheckIns: [:],
            initialMorningStates: [],
            initialHiddenInterventions: [],
            persistUserDataPatch: { _ in true },
            accessibilityAnnouncer: accessibilityAnnouncer
        )
    }

    init(
        snapshot: DashboardSnapshot,
        graphData: CausalGraphData,
        initialExperienceFlow: ExperienceFlow = .empty,
        initialDailyCheckIns: [String: [String]] = [:],
        initialMorningStates: [MorningState] = [],
        initialHiddenInterventions: [String] = [],
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true },
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
        morningStates = initialMorningStates
        hiddenInterventions = initialHiddenInterventions

        inputCheckOperationToken = 0
        inputHiddenOperationToken = 0
        morningOutcomeOperationToken = 0

        self.persistUserDataPatch = persistUserDataPatch
        self.nowProvider = nowProvider
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func openProfileSheet() {
        isProfileSheetPresented = true
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

    func toggleInputCheckedToday(_ inputID: String) {
        guard mode == .explore else { return }
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }

        let currentInput = snapshot.inputs[index]
        let previousSnapshot = snapshot
        let previousDailyCheckIns = dailyCheckIns

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

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            statusText: nextStatusText,
            completion: Double(nextDayCount) / 7.0,
            isCheckedToday: nextCheckedToday,
            classificationText: currentInput.classificationText,
            isHidden: currentInput.isHidden,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink
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

        let successMessage = nextCheckedToday
            ? "\(currentInput.name) checked for today."
            : "\(currentInput.name) unchecked for today."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextInputCheckOperationToken()
        Task {
            do {
                try await persistPatch(.dailyCheckIns(nextDailyCheckIns))
            } catch {
                guard operationToken == inputCheckOperationToken else { return }
                dailyCheckIns = previousDailyCheckIns
                snapshot = previousSnapshot
                let failureMessage = "Could not save \(currentInput.name) check-in. Reverted."
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
    }

    func toggleInputHidden(_ inputID: String) {
        guard mode == .explore else { return }
        guard let index = snapshot.inputs.firstIndex(where: { $0.id == inputID }) else { return }

        let currentInput = snapshot.inputs[index]
        let previousSnapshot = snapshot
        let previousHiddenInterventions = hiddenInterventions
        let nextHidden = !currentInput.isHidden

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            statusText: currentInput.statusText,
            completion: currentInput.completion,
            isCheckedToday: currentInput.isCheckedToday,
            classificationText: currentInput.classificationText,
            isHidden: nextHidden,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink
        )

        let nextHiddenInterventions = Self.updatedHiddenInterventions(
            from: hiddenInterventions,
            interventionID: currentInput.id,
            isHidden: nextHidden
        )

        updateInput(nextInput, at: index)
        hiddenInterventions = nextHiddenInterventions

        let successMessage = nextHidden
            ? "\(currentInput.name) muted."
            : "\(currentInput.name) unmuted."
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextInputHiddenOperationToken()
        Task {
            do {
                try await persistPatch(.hiddenInterventions(nextHiddenInterventions))
            } catch {
                guard operationToken == inputHiddenOperationToken else { return }
                hiddenInterventions = previousHiddenInterventions
                snapshot = previousSnapshot
                let failureMessage = "Could not save mute state for \(currentInput.name). Reverted."
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
        case .edgeSelected(_, _, let sourceLabel, let targetLabel, _):
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

    private func nextInputHiddenOperationToken() -> Int {
        inputHiddenOperationToken += 1
        return inputHiddenOperationToken
    }

    private func nextMorningOutcomeOperationToken() -> Int {
        morningOutcomeOperationToken += 1
        return morningOutcomeOperationToken
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

    private static func updatedHiddenInterventions(
        from current: [String],
        interventionID: String,
        isHidden: Bool
    ) -> [String] {
        var next = current

        if isHidden {
            if !next.contains(interventionID) {
                next.append(interventionID)
            }
            return next
        }

        next.removeAll { $0 == interventionID }
        return next
    }

    private static func resolveNodeID(from graphData: CausalGraphData, focusedNodeLabel: String) -> String? {
        graphData.nodes.first {
            firstLine(for: $0.data.label) == focusedNodeLabel
        }?.data.id
    }

    private static func firstLine(for label: String) -> String {
        label.components(separatedBy: "\n").first ?? label
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
            healthAnxiety: state.healthAnxiety.map { Int($0.rounded()) }
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
            createdAt: existingCreatedAt
        )
        return mutableStates
    }

    private static func timestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private enum PersistenceError: Error {
    case writeRejected
}
