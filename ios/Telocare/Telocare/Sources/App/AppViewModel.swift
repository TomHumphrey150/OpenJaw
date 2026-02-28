import Combine
import Foundation

private let defaultMuseDiagnosticsPollingIntervalNanoseconds: UInt64 = 1_000_000_000

enum AppleHealthRefreshTrigger: Sendable {
    case manual
    case automatic
    case postConnect
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var mode: AppMode
    @Published private(set) var guidedStep: GuidedStep
    @Published private(set) var snapshot: DashboardSnapshot {
        didSet {
            scheduleProjectionPublish()
        }
    }
    @Published private(set) var isProfileSheetPresented: Bool
    @Published private(set) var selectedExploreTab: ExploreTab
    @Published private(set) var exploreFeedback: String
    @Published private(set) var graphData: CausalGraphData {
        didSet {
            scheduleProjectionPublish()
        }
    }
    @Published private(set) var graphDisplayFlags: GraphDisplayFlags
    @Published private(set) var focusedNodeID: String?
    @Published private(set) var graphSelectionText: String
    @Published private(set) var morningOutcomeSelection: MorningOutcomeSelection
    @Published private(set) var museConnectionState: MuseConnectionState
    @Published private(set) var museRecordingState: MuseRecordingState
    @Published private(set) var museLiveDiagnostics: MuseLiveDiagnostics?
    @Published private(set) var isMuseFitCalibrationPresented: Bool
    @Published private(set) var museFitDiagnostics: MuseLiveDiagnostics?
    @Published private(set) var museFitReadyStreakSeconds: Int
    @Published private(set) var museFitPrimaryBlockerText: String?
    @Published private(set) var museSetupDiagnosticsFileURLs: [URL]
    @Published private(set) var museSessionFeedback: String
    @Published private(set) var pendingGraphPatchPreview: GraphPatchPreview?
    @Published private(set) var pendingGraphPatchConflicts: [GraphPatchConflict]
    @Published private(set) var pendingGraphPatchConflictResolutions: [Int: GraphConflictResolutionChoice]
    @Published private(set) var graphCheckpointVersions: [String]
    @Published private(set) var progressQuestionProposal: ProgressQuestionSetProposal?
    @Published private(set) var isProgressQuestionProposalPresented: Bool
    @Published var chatDraft: String

    private var experienceFlow: ExperienceFlow
    private var dailyCheckIns: [String: [String]]
    private var dailyDoseProgress: [String: [String: Double]]
    private var interventionCompletionEvents: [InterventionCompletionEvent]
    private var interventionDoseSettings: [String: DoseSettings]
    private var appleHealthConnections: [String: AppleHealthConnection]
    private var appleHealthValues: [String: Double]
    private var appleHealthReferenceValues: [String: Double]
    private var nightOutcomes: [NightOutcome]
    private var morningStates: [MorningState]
    private var activeInterventions: [String]
    private var inputCheckOperationToken: Int
    private var inputDoseOperationToken: Int
    private var inputDoseSettingsOperationToken: Int
    private var inputActiveOperationToken: Int
    private var appleHealthConnectionOperationToken: Int
    private var morningOutcomeOperationToken: Int
    private var graphDeactivationOperationToken: Int
    private var museSessionOperationToken: Int
    private var museOutcomeSaveOperationToken: Int
    private var museDiagnosticsPollingTask: Task<Void, Never>?
    private var museFitDiagnosticsPollingTask: Task<Void, Never>?
    private var projectionPublishTask: Task<Void, Never>?
    private var museRecordingStartedWithFitOverride: Bool
    private var progressQuestionSetState: ProgressQuestionSetState?
    private var gardenAliasOverrides: [GardenAliasOverride]
    private var pendingGraphPatchEnvelope: GraphPatchEnvelope?
    private let configuredMorningOutcomeFields: [MorningOutcomeField]
    private let requiredMorningOutcomeFields: [MorningOutcomeField]
    private let configuredMorningTrendMetrics: [MorningTrendMetric]

    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private let persistUserDataPatch: @Sendable (UserDataPatch) async throws -> Bool
    private let appleHealthDoseService: AppleHealthDoseService
    private let museSessionService: MuseSessionService
    private let museLicenseData: Data?
    private let nowProvider: () -> Date
    private let museDiagnosticsPollingIntervalNanoseconds: UInt64
    private let graphMutationService: GraphMutationService
    private let inputMutationService: InputMutationService
    private let morningOutcomeMutationService: MorningOutcomeMutationService
    private let appleHealthSyncCoordinator: AppleHealthSyncCoordinator
    private let museSessionCoordinator: MuseSessionCoordinator
    private let graphKernel: GraphKernel
    private let graphProjectionHub: GraphProjectionHub
    private let graphPatchCodec: GraphPatchJSONCodec
    private let progressQuestionProposalBuilder: ProgressQuestionProposalBuilder
    private static let maxCompletionEventsPerIntervention = 200
    private static let minimumMuseRecordingMinutes = 120.0
    private static let museOutcomeSource = "muse_athena_heuristic_v1"
    private static let requiredMuseFitReadySeconds = 20
    private static let museFitMinimumHeadbandCoverage = 0.80
    private static let museFitMinimumQualityGateCoverage = 0.60
    private static let defaultCollapsedHierarchyParents: Set<String> = ["STRESS", "GERD", "EXTERNAL_TRIGGERS", "RMMA", "GABA_DEF"]
    private static let defaultExpandedHierarchyParents: Set<String> = ["OSA", "SLEEP_DEP", "MICRO"]
    private typealias HierarchyLegacyParentRemap = (from: String, to: [String]?)
    private static let hierarchyLegacyParentRemapsByNodeID: [String: [HierarchyLegacyParentRemap]] = [
        "OSA": [(from: "GERD", to: nil)],
        "AIRWAY_OBS": [(from: "GERD", to: ["OSA"])],
        "NEG_PRESSURE": [(from: "GERD", to: ["AIRWAY_OBS"])],
        "SLEEP_DEP": [(from: "STRESS", to: nil)],
        "CAFFEINE": [(from: "STRESS", to: ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"])],
        "ALCOHOL": [(from: "STRESS", to: ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"])],
        "SMOKING": [(from: "STRESS", to: ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"])],
        "SSRI": [(from: "STRESS", to: ["EXTERNAL_TRIGGERS", "RMMA"])],
        "GENETICS": [(from: "STRESS", to: ["MICRO"])],
        "MICRO": [(from: "RMMA", to: nil)],
        "FHP": [(from: "RMMA", to: ["TMD"])],
        "CERVICAL": [(from: "RMMA", to: ["TMD"])],
        "HYOID": [(from: "RMMA", to: ["TMD"])],
        "CS": [(from: "RMMA", to: ["TMD"])],
        "WINDUP": [(from: "RMMA", to: ["CS"])],
        "HEADACHES": [(from: "RMMA", to: ["CS"])],
        "NECK_TIGHTNESS": [(from: "RMMA", to: ["CS"])],
        "GLOBUS": [(from: "RMMA", to: ["CS"])],
        "EAR": [(from: "RMMA", to: ["TMD"])],
    ]
    private static let hierarchyParentIDsMap: [String: [String]] = [
        "HEALTH_ANXIETY": ["STRESS"],
        "CORTISOL": ["STRESS"],
        "CATECHOL": ["STRESS"],
        "SYMPATHETIC": ["STRESS"],
        "CAFFEINE": ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"],
        "ALCOHOL": ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"],
        "SMOKING": ["EXTERNAL_TRIGGERS", "SLEEP_DEP", "GERD"],
        "SSRI": ["EXTERNAL_TRIGGERS", "RMMA"],
        "GENETICS": ["MICRO"],
        "AIRWAY_OBS": ["OSA"],
        "NEG_PRESSURE": ["AIRWAY_OBS"],
        "TLESR": ["GERD"],
        "ACID": ["GERD"],
        "VAGAL": ["ACID"],
        "PEPSIN": ["GERD"],
        "DOPAMINE": ["GABA_DEF"],
        "MG_DEF": ["GABA_DEF"],
        "VIT_D": ["GABA_DEF"],
        "RMMA": ["MICRO"],
        "GRINDING": ["RMMA"],
        "TOOTH": ["GRINDING"],
        "SALIVA": ["RMMA"],
        "TMD": ["RMMA"],
        "FHP": ["TMD"],
        "CERVICAL": ["TMD"],
        "HYOID": ["TMD"],
        "EAR": ["TMD"],
        "CS": ["TMD"],
        "WINDUP": ["CS"],
        "NECK_TIGHTNESS": ["CS"],
        "HEADACHES": ["CS"],
        "GLOBUS": ["CS"],
        "OSA_TX": ["OSA"],
        "TONGUE_TX": ["OSA"],
        "PPI_TX": ["GERD"],
        "MORNING_FAST_TX": ["GERD"],
        "REFLUX_DIET_TX": ["GERD"],
        "MEAL_TIMING_TX": ["GERD"],
        "BED_ELEV_TX": ["GERD"],
        "CIRCADIAN_TX": ["SLEEP_DEP"],
        "SLEEP_HYG_TX": ["SLEEP_DEP"],
        "SCREENS_TX": ["SLEEP_DEP"],
        "EXERCISE_TX": ["SLEEP_DEP"],
        "MINDFULNESS_TX": ["STRESS"],
        "NATURE_TX": ["STRESS"],
        "CBT_TX": ["STRESS"],
        "BREATHING_TX": ["STRESS"],
        "WARM_SHOWER_TX": ["STRESS"],
        "NEUROSYM_TX": ["STRESS"],
        "MG_SUPP": ["GABA_DEF"],
        "THEANINE_TX": ["GABA_DEF"],
        "GLYCINE_TX": ["GABA_DEF"],
        "YOGA_TX": ["GABA_DEF"],
        "VIT_D_TX": ["VIT_D"],
        "MULTI_TX": ["MG_DEF"],
        "JAW_RELAX_TX": ["RMMA"],
        "BIOFEEDBACK_TX": ["RMMA"],
        "BOTOX_TX": ["RMMA"],
        "PHYSIO_TX": ["TMD"],
        "POSTURE_TX": ["TMD"],
        "MASSAGE_TX": ["TMD"],
        "HEAT_TX": ["TMD"],
        "HYDRATION": ["SALIVA"],
        "SPLINT": ["GRINDING"],
        "SSRI_TX": ["SSRI"],
    ]

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
            initialNightOutcomes: [],
            initialMorningStates: [],
            initialMorningQuestionnaire: nil,
            initialActiveInterventions: [],
            persistUserDataPatch: { _ in true },
            appleHealthDoseService: MockAppleHealthDoseService(),
            museSessionService: MockMuseSessionService(),
            museLicenseData: nil,
            museDiagnosticsPollingIntervalNanoseconds: defaultMuseDiagnosticsPollingIntervalNanoseconds,
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
        initialNightOutcomes: [NightOutcome] = [],
        initialMorningStates: [MorningState] = [],
        initialMorningQuestionnaire: MorningQuestionnaire? = nil,
        initialProgressQuestionSetState: ProgressQuestionSetState? = nil,
        initialGardenAliasOverrides: [GardenAliasOverride] = [],
        initialCustomCausalDiagram: CustomCausalDiagram? = nil,
        initialActiveInterventions: [String] = [],
        persistUserDataPatch: @escaping @Sendable (UserDataPatch) async throws -> Bool = { _ in true },
        appleHealthDoseService: AppleHealthDoseService = MockAppleHealthDoseService(),
        museSessionService: MuseSessionService = MockMuseSessionService(),
        museLicenseData: Data? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        museDiagnosticsPollingIntervalNanoseconds: UInt64 = defaultMuseDiagnosticsPollingIntervalNanoseconds,
        graphMutationService: GraphMutationService = DefaultGraphMutationService(),
        inputMutationService: InputMutationService = DefaultInputMutationService(),
        morningOutcomeMutationService: MorningOutcomeMutationService = DefaultMorningOutcomeMutationService(),
        appleHealthSyncCoordinator: AppleHealthSyncCoordinator? = nil,
        museSessionCoordinator: MuseSessionCoordinator = DefaultMuseSessionCoordinator(),
        progressQuestionProposalBuilder: ProgressQuestionProposalBuilder = ProgressQuestionProposalBuilder(),
        accessibilityAnnouncer: AccessibilityAnnouncer
    ) {
        let todayKey = Self.localDateKey(from: nowProvider())
        let seededGraphData = Self.seedHierarchyIfNeeded(graphData)
        let resolvedMorningOutcomeFields = Self.resolveMorningOutcomeFields(from: initialMorningQuestionnaire)
        let resolvedRequiredMorningOutcomeFields = Self.resolveRequiredMorningOutcomeFields(
            enabledFields: resolvedMorningOutcomeFields,
            questionnaire: initialMorningQuestionnaire
        )
        let resolvedMorningTrendMetrics = Self.resolveMorningTrendMetrics(from: resolvedMorningOutcomeFields)

        mode = .explore
        guidedStep = .outcomes
        self.snapshot = snapshot
        isProfileSheetPresented = false
        selectedExploreTab = .inputs
        exploreFeedback = "AI chat backend is not connected yet."
        self.graphData = seededGraphData
        graphDisplayFlags = GraphDisplayFlags(
            showFeedbackEdges: false,
            showProtectiveEdges: false,
            showInterventionNodes: false
        )
        focusedNodeID = Self.resolveNodeID(from: seededGraphData, focusedNodeLabel: snapshot.situation.focusedNode)
        graphSelectionText = "Graph ready."
        morningOutcomeSelection = Self.morningOutcomeSelection(for: todayKey, from: initialMorningStates)
        museConnectionState = .disconnected
        museRecordingState = .idle
        museLiveDiagnostics = nil
        isMuseFitCalibrationPresented = false
        museFitDiagnostics = nil
        museFitReadyStreakSeconds = 0
        museFitPrimaryBlockerText = nil
        museSetupDiagnosticsFileURLs = []
        museSessionFeedback = "Muse session idle."
        pendingGraphPatchPreview = nil
        pendingGraphPatchConflicts = []
        pendingGraphPatchConflictResolutions = [:]
        graphCheckpointVersions = []
        progressQuestionProposal = nil
        isProgressQuestionProposalPresented = false
        chatDraft = ""
        configuredMorningOutcomeFields = resolvedMorningOutcomeFields
        requiredMorningOutcomeFields = resolvedRequiredMorningOutcomeFields
        configuredMorningTrendMetrics = resolvedMorningTrendMetrics

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
        appleHealthReferenceValues = [:]
        nightOutcomes = initialNightOutcomes
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
        museSessionOperationToken = 0
        museOutcomeSaveOperationToken = 0
        museDiagnosticsPollingTask = nil
        museFitDiagnosticsPollingTask = nil
        projectionPublishTask = nil
        museRecordingStartedWithFitOverride = false
        progressQuestionSetState = initialProgressQuestionSetState
        gardenAliasOverrides = initialGardenAliasOverrides
        pendingGraphPatchEnvelope = nil

        self.persistUserDataPatch = persistUserDataPatch
        self.appleHealthDoseService = appleHealthDoseService
        self.museSessionService = museSessionService
        self.museLicenseData = museLicenseData
        self.nowProvider = nowProvider
        self.museDiagnosticsPollingIntervalNanoseconds = museDiagnosticsPollingIntervalNanoseconds
        self.graphMutationService = graphMutationService
        self.inputMutationService = inputMutationService
        self.morningOutcomeMutationService = morningOutcomeMutationService
        self.appleHealthSyncCoordinator = appleHealthSyncCoordinator
            ?? DefaultAppleHealthSyncCoordinator(appleHealthDoseService: appleHealthDoseService)
        self.museSessionCoordinator = museSessionCoordinator
        let initialDiagram = initialCustomCausalDiagram
            ?? CustomCausalDiagram(
                graphData: seededGraphData,
                lastModified: DateKeying.timestamp(from: nowProvider()),
                graphVersion: nil,
                baseGraphVersion: nil
            )
        graphKernel = GraphKernel(
            diagram: initialDiagram,
            aliasOverrides: initialGardenAliasOverrides
        )
        graphProjectionHub = GraphProjectionHub(
            inputs: snapshot.inputs,
            graphData: seededGraphData,
            graphVersion: initialDiagram.graphVersion,
            questionSetState: initialProgressQuestionSetState
        )
        graphPatchCodec = GraphPatchJSONCodec()
        self.progressQuestionProposalBuilder = progressQuestionProposalBuilder
        self.accessibilityAnnouncer = accessibilityAnnouncer

        Task {
            await publishGraphProjections()
        }
    }

    func openProfileSheet() {
        isProfileSheetPresented = true
    }

    var morningStateHistory: [MorningState] {
        morningStates
    }

    var morningCheckInFields: [MorningOutcomeField] {
        configuredMorningOutcomeFields
    }

    var requiredMorningCheckInFields: [MorningOutcomeField] {
        requiredMorningOutcomeFields
    }

    var morningTrendMetricOptions: [MorningTrendMetric] {
        configuredMorningTrendMetrics
    }

    var projectedInputs: [InputStatus] {
        graphProjectionHub.habits.inputs
    }

    var projectedGuideGraphVersion: String? {
        graphProjectionHub.guide.graphVersion
    }

    var museConnectionStatusText: String {
        switch museConnectionState {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning"
        case .discovered(let headband):
            return "Discovered \(headband.name)"
        case .connecting(let headband):
            return "Connecting to \(headband.name)"
        case .connected(let headband):
            return "Connected to \(headband.name)"
        case .needsLicense:
            return "Needs license"
        case .needsUpdate:
            return "Needs device update"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    var museRecordingStatusText: String {
        switch museRecordingState {
        case .idle:
            return "Not recording"
        case .recording(let startedAt):
            let minutes = max(0, nowProvider().timeIntervalSince(startedAt) / 60.0)
            return "Recording (\(Self.formattedMinutes(minutes)))"
        case .stopped(let summary):
            return "Stopped (\(Self.formattedMinutes(summary.totalSleepMinutes)))"
        }
    }

    var museCanScan: Bool {
        switch museConnectionState {
        case .disconnected, .failed, .needsLicense, .needsUpdate:
            return true
        case .scanning, .discovered, .connecting, .connected:
            return false
        }
    }

    var museCanConnect: Bool {
        if case .discovered = museConnectionState {
            return true
        }

        return false
    }

    var museCanDisconnect: Bool {
        switch museConnectionState {
        case .disconnected, .needsLicense, .needsUpdate, .failed:
            return false
        case .scanning, .discovered, .connecting, .connected:
            return true
        }
    }

    var museCanStartRecording: Bool {
        guard case .connected = museConnectionState else {
            return false
        }

        guard case .idle = museRecordingState else {
            return false
        }

        return true
    }

    var museFitReadyRequiredSeconds: Int {
        Self.requiredMuseFitReadySeconds
    }

    var museCanStartRecordingFromFitCalibration: Bool {
        museFitReadyStreakSeconds >= Self.requiredMuseFitReadySeconds
    }

    var museCanStartRecordingWithFitOverride: Bool {
        guard isMuseFitCalibrationPresented else {
            return false
        }
        guard case .connected = museConnectionState else {
            return false
        }
        guard case .idle = museRecordingState else {
            return false
        }

        return !museCanStartRecordingFromFitCalibration
    }

    var museCanStopRecording: Bool {
        if case .recording = museRecordingState {
            return true
        }

        return false
    }

    var museIsRecording: Bool {
        if case .recording = museRecordingState {
            return true
        }

        return false
    }

    var museCanSaveNightOutcome: Bool {
        guard case .stopped(let summary) = museRecordingState else {
            return false
        }

        return summary.totalSleepMinutes >= Self.minimumMuseRecordingMinutes
    }

    var museRecordingSummary: MuseRecordingSummary? {
        if case .stopped(let summary) = museRecordingState {
            return summary
        }

        return nil
    }

    var museDisclaimerText: String {
        "Muse output is a non-diagnostic wellness signal and does not diagnose or treat medical conditions."
    }

    func setProfileSheetPresented(_ isPresented: Bool) {
        isProfileSheetPresented = isPresented
    }

    func scanForMuseHeadband() {
        guard mode == .explore else { return }

        let operationToken = nextMuseSessionOperationToken()
        museConnectionState = .scanning
        let message = "Scanning for Muse headbands."
        museSessionFeedback = message
        announce(message)

        Task {
            do {
                let headbands = try await museSessionService.scanForHeadbands()
                guard operationToken == museSessionOperationToken else { return }
                guard let headband = headbands.first else {
                    museConnectionState = .disconnected
                    let emptyMessage = "No Muse headbands found."
                    museSessionFeedback = emptyMessage
                    announce(emptyMessage)
                    return
                }

                museConnectionState = .discovered(headband)
                let successMessage = "Found \(headband.name)."
                museSessionFeedback = successMessage
                announce(successMessage)
            } catch {
                guard operationToken == museSessionOperationToken else { return }
                applyMuseSessionError(error, fallback: "Could not scan for Muse headbands.")
            }
        }
    }

    func connectToMuseHeadband() {
        guard mode == .explore else { return }
        guard case .discovered(let headband) = museConnectionState else { return }

        let operationToken = nextMuseSessionOperationToken()
        museConnectionState = .connecting(headband)
        let message = "Connecting to \(headband.name)."
        museSessionFeedback = message
        announce(message)

        Task {
            do {
                try await museSessionService.connect(to: headband, licenseData: museLicenseData)
                guard operationToken == museSessionOperationToken else { return }
                museConnectionState = .connected(headband)
                if isMuseFitCalibrationPresented {
                    startMuseFitDiagnosticsPolling()
                }
                await refreshMuseSetupDiagnosticsAvailability()
                let successMessage = "Connected to \(headband.name)."
                museSessionFeedback = successMessage
                announce(successMessage)
            } catch {
                guard operationToken == museSessionOperationToken else { return }
                applyMuseSessionError(error, fallback: "Could not connect to \(headband.name).")
            }
        }
    }

    func disconnectMuseHeadband() {
        guard mode == .explore else { return }

        stopMuseDiagnosticsPolling(clearDiagnostics: true)
        stopMuseFitDiagnosticsPolling(clearDiagnostics: true)
        isMuseFitCalibrationPresented = false
        museRecordingStartedWithFitOverride = false
        museFitPrimaryBlockerText = nil
        let operationToken = nextMuseSessionOperationToken()
        Task {
            await museSessionService.disconnect()
            guard operationToken == museSessionOperationToken else { return }
            await refreshMuseSetupDiagnosticsAvailability()
            if case .recording = museRecordingState {
                museRecordingState = .idle
            }
            museConnectionState = .disconnected
            let message = "Muse disconnected."
            museSessionFeedback = message
            announce(message)
        }
    }

    func startMuseRecording() {
        guard mode == .explore else { return }
        guard case .connected = museConnectionState else { return }
        guard case .idle = museRecordingState else { return }

        isMuseFitCalibrationPresented = true
        museFitReadyStreakSeconds = 0
        museFitDiagnostics = nil
        startMuseFitDiagnosticsPolling()
        MuseDiagnosticsLogger.info("Muse fit calibration opened")
        let message = "Fit calibration opened. Adjust fit until ready, or start anyway with low reliability."
        museSessionFeedback = message
        announce(message)
    }

    func dismissMuseFitCalibration() {
        guard isMuseFitCalibrationPresented else { return }
        isMuseFitCalibrationPresented = false
        stopMuseFitDiagnosticsPolling(clearDiagnostics: true)
        Task {
            _ = await exportMuseSetupDiagnosticsSnapshot()
        }
        MuseDiagnosticsLogger.info("Muse fit calibration closed")
    }

    func exportMuseSetupDiagnosticsSnapshot() async -> [URL] {
        let setupFileURLs = await museSessionService.snapshotSetupDiagnostics(at: nowProvider())
        museSetupDiagnosticsFileURLs = setupFileURLs
        return setupFileURLs
    }

    func refreshMuseSetupDiagnosticsAvailability() async {
        museSetupDiagnosticsFileURLs = await museSessionService.latestSetupDiagnosticsFileURLs()
    }

    func startMuseRecordingFromFitCalibration() {
        guard museCanStartRecordingFromFitCalibration else {
            return
        }

        beginMuseRecording(startedWithFitOverride: false)
    }

    func startMuseRecordingWithFitOverride() {
        guard museCanStartRecordingWithFitOverride else {
            return
        }

        beginMuseRecording(startedWithFitOverride: true)
    }

    func stopMuseRecording() {
        guard mode == .explore else { return }
        guard case .recording = museRecordingState else { return }
        stopMuseRecordingForCurrentState()
    }

    private func beginMuseRecording(startedWithFitOverride: Bool) {
        guard mode == .explore else { return }
        guard case .connected = museConnectionState else { return }
        guard case .idle = museRecordingState else { return }

        let operationToken = nextMuseSessionOperationToken()
        let startDate = nowProvider()
        let fitSnapshot = museFitDiagnostics

        museRecordingStartedWithFitOverride = startedWithFitOverride
        isMuseFitCalibrationPresented = false
        stopMuseFitDiagnosticsPolling(clearDiagnostics: true)
        museRecordingState = .recording(startedAt: startDate)

        if let fitSnapshot {
            MuseDiagnosticsLogger.info(
                "Muse fit start snapshot confidence=\(fitSnapshot.signalConfidence) awake=\(fitSnapshot.awakeLikelihood) headband=\(fitSnapshot.headbandOnCoverage) quality=\(fitSnapshot.qualityGateCoverage) guidance=\(fitSnapshot.fitGuidance.rawValue)"
            )
        } else {
            MuseDiagnosticsLogger.info("Muse fit start snapshot unavailable")
        }

        let message: String
        if startedWithFitOverride {
            MuseDiagnosticsLogger.warn("Muse fit override start used")
            message = "Recording started with low reliability warning. Keep Telocare open in the foreground."
            announce("Starting with low reliability warning")
        } else {
            message = "Recording started. Keep Telocare open in the foreground."
        }

        museSessionFeedback = message
        startMuseDiagnosticsPolling()
        announce(message)

        Task {
            do {
                try await museSessionService.startRecording(at: startDate)
                guard operationToken == museSessionOperationToken else { return }
                await refreshMuseSetupDiagnosticsAvailability()
            } catch {
                guard operationToken == museSessionOperationToken else { return }
                stopMuseDiagnosticsPolling(clearDiagnostics: true)
                museRecordingState = .idle
                museRecordingStartedWithFitOverride = false
                await refreshMuseSetupDiagnosticsAvailability()
                applyMuseSessionError(error, fallback: "Could not start recording.")
            }
        }
    }

    func saveMuseNightOutcome() {
        guard mode == .explore else { return }
        guard case .stopped(let summary) = museRecordingState else { return }
        guard summary.totalSleepMinutes >= Self.minimumMuseRecordingMinutes else {
            let message = "Recording must be at least 2 hours to save."
            museSessionFeedback = message
            announce(message)
            return
        }

        let previousSnapshot = snapshot
        let previousNightOutcomes = nightOutcomes
        let nightID = Self.localDateKey(from: nowProvider())
        let createdAt = Self.timestamp(from: nowProvider())
        let nextOutcome = NightOutcome(
            nightId: nightID,
            microArousalCount: summary.microArousalCount,
            microArousalRatePerHour: summary.microArousalRatePerHour,
            confidence: summary.confidence,
            totalSleepMinutes: summary.totalSleepMinutes,
            source: Self.museOutcomeSource,
            createdAt: createdAt
        )
        let nextNightOutcomes = Self.upsert(nightOutcome: nextOutcome, in: nightOutcomes)
        let nextOutcomeRecords = Self.outcomeRecords(from: nextNightOutcomes)

        nightOutcomes = nextNightOutcomes
        updateOutcomeRecords(nextOutcomeRecords)

        let successMessage = "Saved Muse night outcome for \(nightID)."
        museSessionFeedback = successMessage
        exploreFeedback = successMessage
        announce(successMessage)

        let operationToken = nextMuseOutcomeSaveOperationToken()
        Task {
            do {
                try await persistPatch(.nightOutcomes(nextNightOutcomes))
                guard operationToken == museOutcomeSaveOperationToken else { return }
                museRecordingState = .idle
            } catch {
                guard operationToken == museOutcomeSaveOperationToken else { return }
                snapshot = previousSnapshot
                nightOutcomes = previousNightOutcomes
                let failureMessage = "Could not save Muse night outcome. Reverted."
                museSessionFeedback = failureMessage
                exploreFeedback = failureMessage
                announce(failureMessage)
            }
        }
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
        presentProgressQuestionProposalIfNeeded(for: tab)
        announce("\(tab.title) tab selected.")
    }

    func performExploreAction(_ action: ExploreContextAction) {
        guard mode == .explore else { return }
        exploreFeedback = action.detail
        announce(action.announcement)
    }

    func applyPendingGraphPatchFromReview() {
        guard mode == .explore else { return }
        applyPendingGraphPatch(command: "apply patch")
    }

    func clearPendingGraphPatchPreview() {
        guard mode == .explore else { return }
        pendingGraphPatchEnvelope = nil
        pendingGraphPatchPreview = nil
        pendingGraphPatchConflicts = []
        pendingGraphPatchConflictResolutions = [:]

        Task {
            await publishGraphProjections()
        }
    }

    func setPendingGraphPatchConflictResolution(
        operationIndex: Int,
        choice: GraphConflictResolutionChoice
    ) {
        guard mode == .explore else { return }
        pendingGraphPatchConflictResolutions[operationIndex] = choice
    }

    func rollbackGraph(to graphVersion: String) {
        guard mode == .explore else { return }
        rollbackGraph(command: "rollback \(graphVersion)")
    }

    func acceptProgressQuestionProposal() {
        guard mode == .explore else { return }
        guard let proposal = progressQuestionProposal else { return }

        let existingDeclines = Set(progressQuestionSetState?.declinedGraphVersions ?? [])
        let nextDeclines = existingDeclines.subtracting([proposal.sourceGraphVersion]).sorted()
        let nextState = ProgressQuestionSetState(
            activeQuestionSetVersion: proposal.proposedQuestionSetVersion,
            activeSourceGraphVersion: proposal.sourceGraphVersion,
            declinedGraphVersions: nextDeclines,
            pendingProposal: nil,
            updatedAt: Self.timestamp(from: nowProvider())
        )
        progressQuestionSetState = nextState
        progressQuestionProposal = nil
        isProgressQuestionProposalPresented = false

        Task {
            do {
                try await persistPatch(.progressQuestionSetState(nextState))
                await publishGraphProjections()
            } catch {
            }
        }
    }

    func declineProgressQuestionProposal() {
        guard mode == .explore else { return }
        guard let proposal = progressQuestionProposal else { return }

        let current = progressQuestionSetState ?? baselineProgressQuestionSetState(for: proposal.sourceGraphVersion)
        let nextDeclines = Set(current.declinedGraphVersions)
            .union([proposal.sourceGraphVersion])
            .sorted()
        let nextState = ProgressQuestionSetState(
            activeQuestionSetVersion: current.activeQuestionSetVersion,
            activeSourceGraphVersion: current.activeSourceGraphVersion,
            declinedGraphVersions: nextDeclines,
            pendingProposal: nil,
            updatedAt: Self.timestamp(from: nowProvider())
        )
        progressQuestionSetState = nextState
        progressQuestionProposal = nil
        isProgressQuestionProposalPresented = false

        Task {
            do {
                try await persistPatch(.progressQuestionSetState(nextState))
                await publishGraphProjections()
            } catch {
            }
        }
    }

    func dismissProgressQuestionProposalPrompt() {
        guard mode == .explore else { return }
        isProgressQuestionProposalPresented = false
    }

    func submitChatPrompt() {
        guard mode == .explore else { return }
        let prompt = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            exploreFeedback = "Enter a request before sending."
            announce(exploreFeedback)
            return
        }
        chatDraft = ""

        if looksLikeGraphPatchPayload(prompt) {
            previewGraphPatch(from: prompt)
            return
        }

        let normalizedPrompt = prompt.lowercased()
        if normalizedPrompt == "apply patch" || normalizedPrompt == "apply patch local" || normalizedPrompt == "apply patch server" {
            applyPendingGraphPatch(command: normalizedPrompt)
            return
        }

        if normalizedPrompt == "export graph" {
            exportGraph()
            return
        }

        if normalizedPrompt.hasPrefix("rollback ") {
            rollbackGraph(command: prompt)
            return
        }

        exploreFeedback = "AI chat backend is not connected yet. Draft not sent: \(prompt)"
        announce("AI chat backend is not connected yet.")
    }

    private func looksLikeGraphPatchPayload(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.contains("\"operations\"")
    }

    private func previewGraphPatch(from rawText: String) {
        let envelope: GraphPatchEnvelope
        do {
            envelope = try graphPatchCodec.decodeEnvelope(from: rawText)
        } catch {
            exploreFeedback = "Patch parse failed. Submit valid JSON with schemaVersion, baseGraphVersion, operations, and explanations."
            announce(exploreFeedback)
            return
        }

        Task {
            do {
                let previewResult = try await graphKernel.preview(envelope)
                pendingGraphPatchEnvelope = previewResult.preview.envelope
                pendingGraphPatchPreview = previewResult.preview
                pendingGraphPatchConflicts = previewResult.conflicts
                pendingGraphPatchConflictResolutions = [:]
                await publishGraphProjections()

                if previewResult.conflicts.isEmpty {
                    exploreFeedback = "Patch preview ready (\(previewResult.preview.summaryLines.joined(separator: ", "))). Send APPLY PATCH to confirm."
                } else {
                    exploreFeedback = "Patch preview has \(previewResult.conflicts.count) conflict(s). Send APPLY PATCH LOCAL or APPLY PATCH SERVER."
                }
                announce(exploreFeedback)
            } catch GraphKernelError.validationFailed(let errors) {
                pendingGraphPatchEnvelope = nil
                pendingGraphPatchPreview = nil
                pendingGraphPatchConflicts = []
                pendingGraphPatchConflictResolutions = [:]
                await publishGraphProjections()
                exploreFeedback = "Patch validation failed: \(errors.joined(separator: " "))"
                announce(exploreFeedback)
            } catch {
                pendingGraphPatchEnvelope = nil
                pendingGraphPatchPreview = nil
                pendingGraphPatchConflicts = []
                pendingGraphPatchConflictResolutions = [:]
                await publishGraphProjections()
                exploreFeedback = "Patch preview failed."
                announce(exploreFeedback)
            }
        }
    }

    private func applyPendingGraphPatch(command: String) {
        guard let envelope = pendingGraphPatchEnvelope else {
            exploreFeedback = "No pending patch preview. Submit patch JSON first."
            announce(exploreFeedback)
            return
        }

        let defaultResolution: GraphConflictResolutionChoice?
        if command.hasSuffix(" server") {
            defaultResolution = .server
        } else if command.hasSuffix(" local") {
            defaultResolution = .local
        } else {
            defaultResolution = nil
        }

        Task {
            var resolutions = pendingGraphPatchConflictResolutions
            if let defaultResolution {
                for conflict in pendingGraphPatchConflicts {
                    resolutions[conflict.operationIndex] = defaultResolution
                }
            }
            pendingGraphPatchConflictResolutions = resolutions

            do {
                let previousGraphData = graphData
                let previousAliasOverrides = gardenAliasOverrides
                let applied = try await graphKernel.apply(envelope, conflictResolutions: resolutions)
                graphData = applied.diagram.graphData
                gardenAliasOverrides = applied.aliasOverrides
                pendingGraphPatchEnvelope = nil
                pendingGraphPatchPreview = nil
                pendingGraphPatchConflicts = []
                pendingGraphPatchConflictResolutions = [:]
                await publishGraphProjections()

                let operationToken = nextGraphDeactivationOperationToken()
                do {
                    try await persistPatch(
                        .customCausalDiagramAndGardenAliasOverrides(
                            applied.diagram,
                            applied.aliasOverrides
                        )
                    )
                    exploreFeedback = "Applied graph patch (\(envelope.operations.count) operations)."
                    announce(exploreFeedback)
                } catch {
                    guard operationToken == graphDeactivationOperationToken else { return }
                    graphData = previousGraphData
                    gardenAliasOverrides = previousAliasOverrides
                    await graphKernel.replaceGraphData(previousGraphData, lastModified: DateKeying.timestamp(from: nowProvider()))
                    await publishGraphProjections()
                    exploreFeedback = "Could not save graph patch. Reverted."
                    announce(exploreFeedback)
                }
            } catch GraphKernelError.unresolvedConflicts {
                exploreFeedback = "Patch has unresolved conflicts. Choose Local or Server for each conflict before applying."
                announce(exploreFeedback)
            } catch {
                exploreFeedback = "Patch apply failed."
                announce(exploreFeedback)
            }
        }
    }

    private func rollbackGraph(command: String) {
        let parts = command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            exploreFeedback = "Rollback command requires a graph version: ROLLBACK <graphVersion>."
            announce(exploreFeedback)
            return
        }

        let graphVersion = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !graphVersion.isEmpty else {
            exploreFeedback = "Rollback command requires a graph version: ROLLBACK <graphVersion>."
            announce(exploreFeedback)
            return
        }

        Task {
            guard let rolledBackDiagram = await graphKernel.rollback(to: graphVersion) else {
                exploreFeedback = "No checkpoint found for \(graphVersion)."
                announce(exploreFeedback)
                return
            }

            graphData = rolledBackDiagram.graphData
            pendingGraphPatchEnvelope = nil
            pendingGraphPatchPreview = nil
            pendingGraphPatchConflicts = []
            pendingGraphPatchConflictResolutions = [:]
            await publishGraphProjections()

            let operationToken = nextGraphDeactivationOperationToken()
            do {
                try await persistPatch(.customCausalDiagram(rolledBackDiagram))
                exploreFeedback = "Rolled back graph to \(graphVersion)."
                announce(exploreFeedback)
            } catch {
                guard operationToken == graphDeactivationOperationToken else { return }
                exploreFeedback = "Rollback could not be persisted."
                announce(exploreFeedback)
            }
        }
    }

    private func exportGraph() {
        Task {
            do {
                let diagram = await graphKernel.currentDiagram()
                let aliases = await graphKernel.currentAliasOverrides()
                let exportText = try graphPatchCodec.encodeGraphExport(
                    diagram: diagram,
                    aliasOverrides: aliases
                )
                exploreFeedback = "Graph export ready. Characters: \(exportText.count)."
                announce(exploreFeedback)
            } catch {
                exploreFeedback = "Graph export failed."
                announce(exploreFeedback)
            }
        }
    }

    private func syncKernelGraphDataWithViewState() {
        Task {
            await graphKernel.replaceGraphData(
                graphData,
                lastModified: DateKeying.timestamp(from: nowProvider())
            )
            await publishGraphProjections()
        }
    }

    private func scheduleProjectionPublish() {
        projectionPublishTask?.cancel()
        projectionPublishTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.publishGraphProjections()
        }
    }

    private func publishGraphProjections() async {
        let diagram = await graphKernel.currentDiagram()
        let checkpoints = await graphKernel.checkpointHistory()
        graphCheckpointVersions = checkpoints.map(\.graphVersion)
        refreshProgressQuestionProposalState(for: diagram.graphVersion)
        graphProjectionHub.publish(
            inputs: snapshot.inputs,
            graphData: graphData,
            graphVersion: diagram.graphVersion,
            questionSetState: progressQuestionSetState,
            checkpointVersions: graphCheckpointVersions,
            pendingConflicts: pendingGraphPatchConflicts,
            pendingPreview: pendingGraphPatchPreview
        )
    }

    private func refreshProgressQuestionProposalState(for graphVersion: String?) {
        guard let graphVersion else {
            progressQuestionProposal = nil
            isProgressQuestionProposalPresented = false
            return
        }

        if progressQuestionSetState == nil {
            let baselineState = baselineProgressQuestionSetState(for: graphVersion)
            progressQuestionSetState = baselineState
            progressQuestionProposal = nil
            isProgressQuestionProposalPresented = false
            return
        }

        guard let existingState = progressQuestionSetState else {
            return
        }

        if existingState.activeSourceGraphVersion == graphVersion {
            progressQuestionProposal = nil
            isProgressQuestionProposalPresented = false
            if existingState.pendingProposal != nil {
                let nextState = ProgressQuestionSetState(
                    activeQuestionSetVersion: existingState.activeQuestionSetVersion,
                    activeSourceGraphVersion: existingState.activeSourceGraphVersion,
                    declinedGraphVersions: existingState.declinedGraphVersions,
                    pendingProposal: nil,
                    updatedAt: Self.timestamp(from: nowProvider())
                )
                progressQuestionSetState = nextState
            }
            return
        }

        if Set(existingState.declinedGraphVersions).contains(graphVersion) {
            progressQuestionProposal = nil
            isProgressQuestionProposalPresented = false
            return
        }

        if let pendingProposal = existingState.pendingProposal,
           pendingProposal.sourceGraphVersion == graphVersion {
            progressQuestionProposal = pendingProposal
            return
        }

        let proposal = buildProgressQuestionSetProposal(for: graphVersion)
        progressQuestionProposal = proposal
        let nextState = ProgressQuestionSetState(
            activeQuestionSetVersion: existingState.activeQuestionSetVersion,
            activeSourceGraphVersion: existingState.activeSourceGraphVersion,
            declinedGraphVersions: existingState.declinedGraphVersions,
            pendingProposal: proposal,
            updatedAt: Self.timestamp(from: nowProvider())
        )
        progressQuestionSetState = nextState
    }

    private func presentProgressQuestionProposalIfNeeded(for tab: ExploreTab) {
        guard tab == .outcomes else {
            return
        }
        guard let proposal = progressQuestionProposal else {
            return
        }
        guard proposal.sourceGraphVersion != progressQuestionSetState?.activeSourceGraphVersion else {
            return
        }
        isProgressQuestionProposalPresented = true
    }

    private func baselineProgressQuestionSetState(for graphVersion: String) -> ProgressQuestionSetState {
        ProgressQuestionSetState(
            activeQuestionSetVersion: "questions-\(graphVersion)",
            activeSourceGraphVersion: graphVersion,
            declinedGraphVersions: [],
            pendingProposal: nil,
            updatedAt: Self.timestamp(from: nowProvider())
        )
    }

    private func buildProgressQuestionSetProposal(for graphVersion: String) -> ProgressQuestionSetProposal {
        progressQuestionProposalBuilder.build(
            graphData: graphData,
            graphVersion: graphVersion,
            createdAt: Self.timestamp(from: nowProvider())
        )
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
        guard let mutation = graphMutationService.toggleNodeDeactivation(
            nodeID: nodeID,
            graphData: graphData,
            at: nowProvider()
        ) else { return }

        let previousGraphData = graphData
        graphData = mutation.graphData
        syncKernelGraphDataWithViewState()
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextGraphDeactivationOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == graphDeactivationOperationToken else { return }
                graphData = previousGraphData
                syncKernelGraphDataWithViewState()
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
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
        guard let mutation = graphMutationService.toggleEdgeDeactivation(
            sourceID: sourceID,
            targetID: targetID,
            label: label,
            edgeType: edgeType,
            graphData: graphData,
            at: nowProvider()
        ) else { return }

        let previousGraphData = graphData
        graphData = mutation.graphData
        syncKernelGraphDataWithViewState()
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextGraphDeactivationOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == graphDeactivationOperationToken else { return }
                graphData = previousGraphData
                syncKernelGraphDataWithViewState()
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    @discardableResult
    func toggleGraphNodeExpanded(_ nodeID: String) -> Bool {
        guard mode == .explore else { return false }
        guard let mutation = graphMutationService.toggleNodeExpansion(
            nodeID: nodeID,
            graphData: graphData,
            at: nowProvider()
        ) else { return false }

        let previousGraphData = graphData
        graphData = mutation.graphData
        syncKernelGraphDataWithViewState()
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextGraphDeactivationOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == graphDeactivationOperationToken else { return }
                graphData = previousGraphData
                syncKernelGraphDataWithViewState()
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }

        return true
    }

    func toggleInputCheckedToday(_ inputID: String) {
        guard mode == .explore else { return }
        let context = InputMutationContext(
            snapshot: snapshot,
            dailyCheckIns: dailyCheckIns,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: interventionCompletionEvents,
            interventionDoseSettings: interventionDoseSettings,
            activeInterventions: activeInterventions,
            now: nowProvider(),
            maxCompletionEventsPerIntervention: Self.maxCompletionEventsPerIntervention
        )
        guard let mutation = inputMutationService.toggleCheckIn(inputID: inputID, context: context) else { return }

        let previousSnapshot = snapshot
        let previousDailyCheckIns = dailyCheckIns
        let previousInterventionCompletionEvents = interventionCompletionEvents

        snapshot = mutation.snapshot
        dailyCheckIns = mutation.dailyCheckIns
        dailyDoseProgress = mutation.dailyDoseProgress
        interventionCompletionEvents = mutation.interventionCompletionEvents
        interventionDoseSettings = mutation.interventionDoseSettings
        activeInterventions = mutation.activeInterventions
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextInputCheckOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == inputCheckOperationToken else { return }
                dailyCheckIns = previousDailyCheckIns
                interventionCompletionEvents = previousInterventionCompletionEvents
                snapshot = previousSnapshot
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
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
            referenceTodayHealthValue: appleHealthReferenceValues[inputID],
            referenceTodayHealthValueLabel: appleHealthSyncCoordinator.referenceLabel(for: config),
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
                await refreshAppleHealth(for: inputID, trigger: .postConnect)
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
        let previousReferenceValues = appleHealthReferenceValues

        appleHealthConnections.removeValue(forKey: inputID)
        appleHealthValues.removeValue(forKey: inputID)
        appleHealthReferenceValues.removeValue(forKey: inputID)

        let nextState = InputAppleHealthState(
            available: true,
            connected: false,
            syncStatus: .disconnected,
            todayHealthValue: nil,
            referenceTodayHealthValue: nil,
            referenceTodayHealthValueLabel: appleHealthSyncCoordinator.referenceLabel(for: config),
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
                appleHealthReferenceValues = previousReferenceValues
                snapshot = previousSnapshot
                let message = "Could not disconnect \(currentInput.name) from Apple Health. Reverted."
                exploreFeedback = message
                announce(message)
            }
        }
    }

    func refreshAppleHealth(
        for inputID: String,
        trigger: AppleHealthRefreshTrigger = .manual
    ) async {
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
            referenceTodayHealthValue: appleHealthReferenceValues[inputID],
            referenceTodayHealthValueLabel: appleHealthSyncCoordinator.referenceLabel(for: config),
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
            try await appleHealthDoseService.requestReadAuthorization(for: [config])
            let healthValue = try await appleHealthDoseService.fetchTodayValue(
                for: config,
                unit: currentDoseState.unit,
                now: nowProvider()
            )
            let referenceValue = await appleHealthSyncCoordinator.fetchReferenceValue(
                config: config,
                unit: currentDoseState.unit,
                now: nowProvider()
            )
            var nextDailyDoseProgressForPatch: [String: [String: Double]]?
            var sanitizedHealthValueForResult: Double?
            if let healthValue {
                let sanitizedHealthValue = max(0, healthValue)
                appleHealthValues[inputID] = sanitizedHealthValue
                sanitizedHealthValueForResult = sanitizedHealthValue
                let dateKey = Self.localDateKey(from: nowProvider())
                let nextDailyDoseProgress = Self.updatedDailyDoseProgressForAppleHealthSync(
                    from: dailyDoseProgress,
                    dateKey: dateKey,
                    interventionID: inputID,
                    value: sanitizedHealthValue
                )
                dailyDoseProgress = nextDailyDoseProgress
                nextDailyDoseProgressForPatch = nextDailyDoseProgress
            } else {
                appleHealthValues.removeValue(forKey: inputID)
            }

            if let referenceValue {
                appleHealthReferenceValues[inputID] = referenceValue
            } else {
                appleHealthReferenceValues.removeValue(forKey: inputID)
            }

            let syncResult = appleHealthSyncCoordinator.successResult(
                existingConnection: appleHealthConnections[inputID],
                healthValue: sanitizedHealthValueForResult,
                referenceValue: referenceValue,
                at: nowProvider()
            )
            let status = syncResult.status
            let syncTimestamp = syncResult.connection.lastSyncAt ?? DateKeying.timestampNow()
            appleHealthConnections[inputID] = syncResult.connection

            if let refreshedIndex = snapshot.inputs.firstIndex(where: { $0.id == inputID }) {
                let refreshedInput = snapshot.inputs[refreshedIndex]
                if let refreshedDoseState = refreshedInput.doseState {
                    let nextAppleHealthState = InputAppleHealthState(
                        available: true,
                        connected: true,
                        syncStatus: status,
                        todayHealthValue: appleHealthValues[inputID],
                        referenceTodayHealthValue: appleHealthReferenceValues[inputID],
                        referenceTodayHealthValueLabel: appleHealthSyncCoordinator.referenceLabel(for: config),
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

            let patchToPersist: UserDataPatch
            if let nextDailyDoseProgressForPatch {
                patchToPersist = .appleHealthConnectionsAndDailyDoseProgress(
                    appleHealthConnections,
                    nextDailyDoseProgressForPatch
                )
            } else {
                patchToPersist = .appleHealthConnections(appleHealthConnections)
            }
            try await persistPatch(patchToPersist)

            if trigger != .automatic {
                let message = healthValue == nil
                    ? "No Apple Health data for \(currentInput.name) today. Using app entries."
                    : "Synced \(currentInput.name) from Apple Health."
                exploreFeedback = message
                announce(message)
            }
        } catch {
            let syncResult = appleHealthSyncCoordinator.failureResult(
                existingConnection: appleHealthConnections[inputID],
                error: error,
                at: nowProvider()
            )
            appleHealthConnections[inputID] = syncResult.connection
            let syncTimestamp = syncResult.connection.lastSyncAt ?? DateKeying.timestampNow()

            if let refreshedIndex = snapshot.inputs.firstIndex(where: { $0.id == inputID }) {
                let refreshedInput = snapshot.inputs[refreshedIndex]
                if let refreshedDoseState = refreshedInput.doseState {
                    let failedState = InputAppleHealthState(
                        available: true,
                        connected: true,
                        syncStatus: .failed,
                        todayHealthValue: appleHealthValues[inputID],
                        referenceTodayHealthValue: appleHealthReferenceValues[inputID],
                        referenceTodayHealthValueLabel: appleHealthSyncCoordinator.referenceLabel(for: config),
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

    func refreshAllConnectedAppleHealth(trigger: AppleHealthRefreshTrigger = .manual) async {
        let connectedInputs = snapshot.inputs.compactMap { input -> String? in
            guard input.appleHealthState?.connected == true else {
                return nil
            }
            return input.id
        }

        for inputID in connectedInputs {
            await refreshAppleHealth(for: inputID, trigger: trigger)
        }
    }

    func updateDoseSettings(_ inputID: String, dailyGoal: Double, increment: Double) {
        guard mode == .explore else { return }
        let context = InputMutationContext(
            snapshot: snapshot,
            dailyCheckIns: dailyCheckIns,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: interventionCompletionEvents,
            interventionDoseSettings: interventionDoseSettings,
            activeInterventions: activeInterventions,
            now: nowProvider(),
            maxCompletionEventsPerIntervention: Self.maxCompletionEventsPerIntervention
        )
        guard let mutation = inputMutationService.updateDoseSettings(
            inputID: inputID,
            dailyGoal: dailyGoal,
            increment: increment,
            context: context
        ) else { return }

        let previousSnapshot = snapshot
        let previousSettings = interventionDoseSettings

        snapshot = mutation.snapshot
        dailyCheckIns = mutation.dailyCheckIns
        dailyDoseProgress = mutation.dailyDoseProgress
        interventionCompletionEvents = mutation.interventionCompletionEvents
        interventionDoseSettings = mutation.interventionDoseSettings
        activeInterventions = mutation.activeInterventions
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextInputDoseSettingsOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == inputDoseSettingsOperationToken else { return }
                interventionDoseSettings = previousSettings
                snapshot = previousSnapshot
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    func toggleInputActive(_ inputID: String) {
        guard mode == .explore else { return }
        let context = InputMutationContext(
            snapshot: snapshot,
            dailyCheckIns: dailyCheckIns,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: interventionCompletionEvents,
            interventionDoseSettings: interventionDoseSettings,
            activeInterventions: activeInterventions,
            now: nowProvider(),
            maxCompletionEventsPerIntervention: Self.maxCompletionEventsPerIntervention
        )
        guard let mutation = inputMutationService.toggleActive(inputID: inputID, context: context) else { return }

        let previousSnapshot = snapshot
        let previousActiveInterventions = activeInterventions

        snapshot = mutation.snapshot
        dailyCheckIns = mutation.dailyCheckIns
        dailyDoseProgress = mutation.dailyDoseProgress
        interventionCompletionEvents = mutation.interventionCompletionEvents
        interventionDoseSettings = mutation.interventionDoseSettings
        activeInterventions = mutation.activeInterventions
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextInputActiveOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == inputActiveOperationToken else { return }
                activeInterventions = previousActiveInterventions
                snapshot = previousSnapshot
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    func setMorningOutcomeValue(_ value: Int?, for field: MorningOutcomeField) {
        guard mode == .explore else { return }
        guard let mutation = morningOutcomeMutationService.setMorningOutcomeValue(
            value,
            field: field,
            selection: morningOutcomeSelection,
            morningStates: morningStates,
            configuredFields: configuredMorningOutcomeFields,
            at: nowProvider()
        ) else { return }

        let previousSelection = morningOutcomeSelection
        let previousMorningStates = morningStates
        morningOutcomeSelection = mutation.morningOutcomeSelection
        morningStates = mutation.morningStates
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextMorningOutcomeOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == morningOutcomeOperationToken else { return }
                morningOutcomeSelection = previousSelection
                morningStates = previousMorningStates
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    func handleAppMovedToBackground() {
        if case .recording = museRecordingState {
            stopMuseRecordingForCurrentState(triggeredByBackground: true)
        }
        if isMuseFitCalibrationPresented {
            isMuseFitCalibrationPresented = false
            stopMuseFitDiagnosticsPolling(clearDiagnostics: true)
            Task {
                _ = await exportMuseSetupDiagnosticsSnapshot()
            }
            MuseDiagnosticsLogger.info("Muse fit calibration closed due to app backgrounding")
        }

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
        case .nodeDoubleTapped(let id, let label):
            focusedNodeID = id
            if toggleGraphNodeExpanded(id) {
                graphSelectionText = "Toggled branch: \(label)."
            } else {
                graphSelectionText = "Selected node: \(label)."
            }
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

    private func startMuseDiagnosticsPolling() {
        stopMuseDiagnosticsPolling(clearDiagnostics: true)
        museDiagnosticsPollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard case .recording = museRecordingState else {
                    return
                }

                let diagnostics = await museSessionService.recordingDiagnostics(at: nowProvider())
                guard !Task.isCancelled else {
                    return
                }
                guard case .recording = museRecordingState else {
                    return
                }

                museLiveDiagnostics = diagnostics
                try? await Task.sleep(nanoseconds: museDiagnosticsPollingIntervalNanoseconds)
            }
        }
    }

    private func stopMuseDiagnosticsPolling(clearDiagnostics: Bool) {
        museDiagnosticsPollingTask?.cancel()
        museDiagnosticsPollingTask = nil
        if clearDiagnostics {
            museLiveDiagnostics = nil
        }
    }

    private func startMuseFitDiagnosticsPolling() {
        stopMuseFitDiagnosticsPolling(clearDiagnostics: true)
        museFitDiagnosticsPollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard isMuseFitCalibrationPresented else {
                    return
                }
                guard case .connected = museConnectionState else {
                    return
                }
                guard case .idle = museRecordingState else {
                    return
                }

                let diagnostics = await museSessionService.fitDiagnostics(at: nowProvider())
                guard !Task.isCancelled else {
                    return
                }
                guard isMuseFitCalibrationPresented else {
                    return
                }
                guard case .connected = museConnectionState else {
                    return
                }
                guard case .idle = museRecordingState else {
                    return
                }

                updateMuseFitReadiness(with: diagnostics)
                museFitDiagnostics = diagnostics
                museFitPrimaryBlockerText = diagnostics?.fitReadiness.primaryBlocker?.displayText
                try? await Task.sleep(nanoseconds: museDiagnosticsPollingIntervalNanoseconds)
            }
        }
    }

    private func stopMuseFitDiagnosticsPolling(clearDiagnostics: Bool) {
        museFitDiagnosticsPollingTask?.cancel()
        museFitDiagnosticsPollingTask = nil
        if clearDiagnostics {
            museFitDiagnostics = nil
            museFitReadyStreakSeconds = 0
            museFitPrimaryBlockerText = nil
        }
    }

    private func updateMuseFitReadiness(with diagnostics: MuseLiveDiagnostics?) {
        let wasReady = museCanStartRecordingFromFitCalibration
        if let diagnostics, isGoodFitSample(diagnostics) {
            museFitReadyStreakSeconds = min(
                Self.requiredMuseFitReadySeconds,
                museFitReadyStreakSeconds + 1
            )
        } else {
            museFitReadyStreakSeconds = 0
        }

        let isReady = museCanStartRecordingFromFitCalibration
        if !wasReady && isReady {
            MuseDiagnosticsLogger.info("Muse fit calibration reached ready threshold at \(nowProvider())")
            announce("Fit ready for recording")
        } else if wasReady && !isReady {
            MuseDiagnosticsLogger.warn("Muse fit calibration dropped below threshold")
            announce("Fit dropped below threshold")
        }
    }

    private func isGoodFitSample(_ diagnostics: MuseLiveDiagnostics) -> Bool {
        diagnostics.fitReadiness.isReady
            && diagnostics.fitGuidance == .good
            && diagnostics.headbandOnCoverage >= Self.museFitMinimumHeadbandCoverage
            && diagnostics.qualityGateCoverage >= Self.museFitMinimumQualityGateCoverage
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

    private func updateOutcomeRecords(_ records: [OutcomeRecord]) {
        snapshot = DashboardSnapshot(
            outcomes: snapshot.outcomes,
            outcomeRecords: records,
            outcomesMetadata: snapshot.outcomesMetadata,
            situation: snapshot.situation,
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

    private func stopMuseRecordingForCurrentState(triggeredByBackground: Bool = false) {
        let operationToken = nextMuseSessionOperationToken()
        let endDate = nowProvider()

        Task {
            do {
                let summary = try await museSessionService.stopRecording(at: endDate)
                guard operationToken == museSessionOperationToken else { return }
                stopMuseDiagnosticsPolling(clearDiagnostics: true)
                let recordingReliability = museSessionCoordinator.recordingReliability(
                    fitGuidance: summary.fitGuidance,
                    startedWithFitOverride: museRecordingStartedWithFitOverride
                )
                let completedSummary = summary.withFitRecordingContext(
                    startedWithFitOverride: museRecordingStartedWithFitOverride,
                    recordingReliability: recordingReliability
                )
                museRecordingState = .stopped(completedSummary)
                museRecordingStartedWithFitOverride = false

                let durationText = Self.formattedMinutes(completedSummary.totalSleepMinutes)
                let isLongEnough = completedSummary.totalSleepMinutes >= Self.minimumMuseRecordingMinutes

                let message: String
                if triggeredByBackground {
                    if isLongEnough {
                        message = "Recording stopped because Telocare moved to background (\(durationText))."
                    } else {
                        message = "Recording stopped in background (\(durationText)). At least 2 hours are required to save."
                    }
                } else if isLongEnough {
                    message = "Recording stopped (\(durationText)). Ready to save."
                } else {
                    message = "Recording stopped (\(durationText)). At least 2 hours are required to save."
                }

                museSessionFeedback = message
                announce(message)
                await refreshMuseSetupDiagnosticsAvailability()
            } catch {
                guard operationToken == museSessionOperationToken else { return }
                stopMuseDiagnosticsPolling(clearDiagnostics: true)
                museRecordingState = .idle
                museRecordingStartedWithFitOverride = false
                await refreshMuseSetupDiagnosticsAvailability()
                let fallback = triggeredByBackground
                    ? "Recording ended because Telocare moved to background."
                    : "Could not stop recording."
                applyMuseSessionError(error, fallback: fallback)
            }
        }
    }

    private func applyMuseSessionError(_ error: Error, fallback: String) {
        let result = museSessionCoordinator.resolveSessionError(error, fallback: fallback)
        if let connectionState = result.connectionState {
            museConnectionState = connectionState
        }

        isMuseFitCalibrationPresented = false
        stopMuseFitDiagnosticsPolling(clearDiagnostics: true)
        museRecordingStartedWithFitOverride = false
        Task {
            await refreshMuseSetupDiagnosticsAvailability()
        }
        museSessionFeedback = result.message
        announce(result.message)
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

    private func nextMuseSessionOperationToken() -> Int {
        museSessionOperationToken += 1
        return museSessionOperationToken
    }

    private func nextMuseOutcomeSaveOperationToken() -> Int {
        museOutcomeSaveOperationToken += 1
        return museOutcomeSaveOperationToken
    }

    private func updateDose(inputID: String, operation: DoseOperation) {
        let context = InputMutationContext(
            snapshot: snapshot,
            dailyCheckIns: dailyCheckIns,
            dailyDoseProgress: dailyDoseProgress,
            interventionCompletionEvents: interventionCompletionEvents,
            interventionDoseSettings: interventionDoseSettings,
            activeInterventions: activeInterventions,
            now: nowProvider(),
            maxCompletionEventsPerIntervention: Self.maxCompletionEventsPerIntervention
        )
        guard let mutation = inputMutationService.mutateDose(
            inputID: inputID,
            operation: operation.asMutationOperation,
            context: context
        ) else { return }

        let previousSnapshot = snapshot
        let previousDailyDoseProgress = dailyDoseProgress
        let previousInterventionCompletionEvents = interventionCompletionEvents

        snapshot = mutation.snapshot
        dailyCheckIns = mutation.dailyCheckIns
        dailyDoseProgress = mutation.dailyDoseProgress
        interventionCompletionEvents = mutation.interventionCompletionEvents
        interventionDoseSettings = mutation.interventionDoseSettings
        activeInterventions = mutation.activeInterventions
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextInputDoseOperationToken()
        Task {
            do {
                try await persistPatch(mutation.patch)
            } catch {
                guard operationToken == inputDoseOperationToken else { return }
                dailyDoseProgress = previousDailyDoseProgress
                interventionCompletionEvents = previousInterventionCompletionEvents
                snapshot = previousSnapshot
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    private func doseStatusText(for state: InputDoseState) -> String {
        let percent = Int((state.completionRaw * 100).rounded())
        return "\(DoseValueFormatter.string(from: state.value))/\(DoseValueFormatter.string(from: state.goal)) \(state.unit.displayName) today (\(percent)%)"
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
            appleHealthState: appleHealthState,
            timeOfDay: currentInput.timeOfDay
        )
    }

    private static func seedHierarchyIfNeeded(_ graphData: CausalGraphData) -> CausalGraphData {
        var didChange = false
        let nextNodes = graphData.nodes.map { element in
            let node = element.data

            let existingParentIDs = node.parentIds ?? node.parentId.map { [$0] }
            let normalizedParentIDs = normalizedParentIDs(for: node.id, existingParentIDs: existingParentIDs)
            let seededParentIDs = normalizedParentIDs ?? hierarchyParentIDsMap[node.id]
            let seededParentID = seededParentIDs?.first
            let seededIsExpanded: Bool?
            if let existingExpansion = node.isExpanded {
                seededIsExpanded = existingExpansion
            } else if defaultCollapsedHierarchyParents.contains(node.id) {
                seededIsExpanded = false
            } else if defaultExpandedHierarchyParents.contains(node.id) {
                seededIsExpanded = true
            } else {
                seededIsExpanded = nil
            }

            guard seededParentIDs != node.parentIds || seededParentID != node.parentId || seededIsExpanded != node.isExpanded else {
                return element
            }

            didChange = true
            return GraphNodeElement(
                data: GraphNodeData(
                    id: node.id,
                    label: node.label,
                    styleClass: node.styleClass,
                    confirmed: node.confirmed,
                    tier: node.tier,
                    tooltip: node.tooltip,
                    isDeactivated: node.isDeactivated,
                    parentIds: seededParentIDs,
                    parentId: seededParentID,
                    isExpanded: seededIsExpanded
                )
            )
        }

        guard didChange else {
            return graphData
        }

        return CausalGraphData(
            nodes: nextNodes,
            edges: graphData.edges
        )
    }

    private static func normalizedParentIDs(for nodeID: String, existingParentIDs: [String]?) -> [String]? {
        guard let existingParentIDs else {
            return nil
        }

        guard let remaps = hierarchyLegacyParentRemapsByNodeID[nodeID] else {
            return deduplicatedParentIDs(existingParentIDs)
        }

        var nextParentIDs: [String] = []
        for parentID in existingParentIDs {
            if let remap = remaps.first(where: { $0.from == parentID }) {
                guard let replacementParentIDs = remap.to else {
                    continue
                }

                nextParentIDs.append(contentsOf: replacementParentIDs)
                continue
            }

            nextParentIDs.append(parentID)
        }

        return deduplicatedParentIDs(nextParentIDs)
    }

    private static func deduplicatedParentIDs(_ parentIDs: [String]) -> [String]? {
        var seenParentIDs = Set<String>()
        var uniqueParentIDs: [String] = []

        for parentID in parentIDs where !parentID.isEmpty {
            guard !seenParentIDs.contains(parentID) else {
                continue
            }

            seenParentIDs.insert(parentID)
            uniqueParentIDs.append(parentID)
        }

        return uniqueParentIDs.isEmpty ? nil : uniqueParentIDs
    }

    private static func updatedDailyDoseProgressForAppleHealthSync(
        from current: [String: [String: Double]],
        dateKey: String,
        interventionID: String,
        value: Double
    ) -> [String: [String: Double]] {
        let sanitizedValue = max(0, value)
        if sanitizedValue <= 0 {
            return current
        }

        var next = current
        var progress = next[dateKey] ?? [:]
        let existingValue = progress[interventionID] ?? 0
        progress[interventionID] = max(existingValue, sanitizedValue)
        next[dateKey] = progress
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

    private static func resolveMorningOutcomeFields(
        from questionnaire: MorningQuestionnaire?
    ) -> [MorningOutcomeField] {
        guard let questionnaire else {
            return MorningOutcomeField.legacyFields
        }

        let mappedEnabledFields = questionnaire.enabledFields.map(Self.morningOutcomeField)
        let dedupedEnabledFields = deduplicatedMorningOutcomeFields(mappedEnabledFields)
        if dedupedEnabledFields.isEmpty {
            return MorningOutcomeField.legacyFields
        }

        return dedupedEnabledFields
    }

    private static func resolveRequiredMorningOutcomeFields(
        enabledFields: [MorningOutcomeField],
        questionnaire: MorningQuestionnaire?
    ) -> [MorningOutcomeField] {
        guard let questionnaire else {
            return enabledFields
        }

        let mappedRequiredFields = (questionnaire.requiredFields ?? questionnaire.enabledFields)
            .map(Self.morningOutcomeField)
        let dedupedRequiredFields = deduplicatedMorningOutcomeFields(mappedRequiredFields)
        let enabledFieldSet = Set(enabledFields)
        let filteredRequiredFields = dedupedRequiredFields.filter { enabledFieldSet.contains($0) }
        if filteredRequiredFields.isEmpty {
            return enabledFields
        }

        return filteredRequiredFields
    }

    private static func resolveMorningTrendMetrics(
        from enabledFields: [MorningOutcomeField]
    ) -> [MorningTrendMetric] {
        let mappedMetrics = enabledFields.map(Self.morningTrendMetric)
        let dedupedMetrics = deduplicatedMorningTrendMetrics(mappedMetrics)
        return [.composite] + dedupedMetrics
    }

    private static func deduplicatedMorningOutcomeFields(
        _ fields: [MorningOutcomeField]
    ) -> [MorningOutcomeField] {
        var dedupedFields: [MorningOutcomeField] = []
        var seenFields = Set<MorningOutcomeField>()

        for field in fields where seenFields.insert(field).inserted {
            dedupedFields.append(field)
        }

        return dedupedFields
    }

    private static func deduplicatedMorningTrendMetrics(
        _ metrics: [MorningTrendMetric]
    ) -> [MorningTrendMetric] {
        var dedupedMetrics: [MorningTrendMetric] = []
        var seenMetrics = Set<MorningTrendMetric>()

        for metric in metrics where seenMetrics.insert(metric).inserted {
            dedupedMetrics.append(metric)
        }

        return dedupedMetrics
    }

    private static func morningOutcomeField(
        from questionField: MorningQuestionField
    ) -> MorningOutcomeField {
        switch questionField {
        case .globalSensation:
            return .globalSensation
        case .neckTightness:
            return .neckTightness
        case .jawSoreness:
            return .jawSoreness
        case .earFullness:
            return .earFullness
        case .healthAnxiety:
            return .healthAnxiety
        case .stressLevel:
            return .stressLevel
        case .morningHeadache:
            return .morningHeadache
        case .dryMouth:
            return .dryMouth
        }
    }

    private static func morningTrendMetric(
        from outcomeField: MorningOutcomeField
    ) -> MorningTrendMetric {
        switch outcomeField {
        case .globalSensation:
            return .globalSensation
        case .neckTightness:
            return .neckTightness
        case .jawSoreness:
            return .jawSoreness
        case .earFullness:
            return .earFullness
        case .healthAnxiety:
            return .healthAnxiety
        case .stressLevel:
            return .stressLevel
        case .morningHeadache:
            return .morningHeadache
        case .dryMouth:
            return .dryMouth
        }
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
            stressLevel: state.stressLevel.map { Int($0.rounded()) },
            morningHeadache: state.morningHeadache.map { Int($0.rounded()) },
            dryMouth: state.dryMouth.map { Int($0.rounded()) }
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
            morningHeadache: morningState.morningHeadache,
            dryMouth: morningState.dryMouth,
            createdAt: existingCreatedAt
        )
        return mutableStates
    }

    private static func upsert(nightOutcome: NightOutcome, in existingOutcomes: [NightOutcome]) -> [NightOutcome] {
        var mutableOutcomes = existingOutcomes
        guard let existingIndex = mutableOutcomes.firstIndex(where: { $0.nightId == nightOutcome.nightId }) else {
            mutableOutcomes.append(nightOutcome)
            return mutableOutcomes.sorted { $0.nightId > $1.nightId }
        }

        mutableOutcomes[existingIndex] = nightOutcome
        return mutableOutcomes.sorted { $0.nightId > $1.nightId }
    }

    private static func outcomeRecords(from nightOutcomes: [NightOutcome]) -> [OutcomeRecord] {
        nightOutcomes
            .sorted { $0.nightId > $1.nightId }
            .map { outcome in
                OutcomeRecord(
                    id: outcome.nightId,
                    microArousalRatePerHour: outcome.microArousalRatePerHour,
                    microArousalCount: outcome.microArousalCount,
                    confidence: outcome.confidence,
                    source: outcome.source
                )
            }
    }

    private static func formattedMinutes(_ minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        let safeMinutes = max(0, roundedMinutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }

    private static func timestampNow() -> String {
        timestamp(from: Date())
    }

    private static func timestamp(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
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

private extension DoseOperation {
    var asMutationOperation: InputDoseMutationOperation {
        switch self {
        case .increment:
            return .increment
        case .decrement:
            return .decrement
        case .reset:
            return .reset
        }
    }
}
