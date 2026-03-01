import Foundation
import Observation

private let defaultMuseDiagnosticsPollingIntervalNanoseconds: UInt64 = 1_000_000_000

enum AppleHealthRefreshTrigger: Sendable {
    case manual
    case automatic
    case postConnect
}

struct GraphCheckpointSummary: Equatable, Sendable, Identifiable {
    let graphVersion: String
    let createdAt: String
    let nodeCount: Int
    let edgeCount: Int

    var id: String {
        graphVersion
    }
}

private struct ResolvedGraphEdgeRow {
    let id: String
    let data: GraphEdgeData
}

@Observable
@MainActor
final class AppViewModel {
    private(set) var mode: AppMode
    private(set) var guidedStep: GuidedStep
    private(set) var snapshot: DashboardSnapshot {
        didSet {
            scheduleProjectionPublish()
        }
    }
    private(set) var isProfileSheetPresented: Bool
    private(set) var selectedExploreTab: ExploreTab
    private(set) var exploreFeedback: String
    private(set) var graphData: CausalGraphData {
        didSet {
            scheduleProjectionPublish()
        }
    }
    private(set) var graphDisplayFlags: GraphDisplayFlags
    private(set) var focusedNodeID: String?
    private(set) var graphSelectionText: String
    private(set) var morningOutcomeSelection: MorningOutcomeSelection
    private(set) var museConnectionState: MuseConnectionState
    private(set) var museRecordingState: MuseRecordingState
    private(set) var museLiveDiagnostics: MuseLiveDiagnostics?
    private(set) var isMuseFitCalibrationPresented: Bool
    private(set) var museFitDiagnostics: MuseLiveDiagnostics?
    private(set) var museFitReadyStreakSeconds: Int
    private(set) var museFitPrimaryBlockerText: String?
    private(set) var museSetupDiagnosticsFileURLs: [URL]
    private(set) var museSessionFeedback: String
    private(set) var pendingGraphPatchPreview: GraphPatchPreview?
    private(set) var pendingGraphPatchConflicts: [GraphPatchConflict]
    private(set) var pendingGraphPatchConflictResolutions: [Int: GraphConflictResolutionChoice]
    private(set) var graphCheckpointVersions: [String]
    private(set) var graphCheckpointSummaries: [GraphCheckpointSummary]
    private(set) var progressQuestionProposal: ProgressQuestionSetProposal?
    private(set) var isProgressQuestionProposalPresented: Bool
    private(set) var plannerAvailableMinutes: Int
    private(set) var plannerTimeBudgetState: DailyTimeBudgetState
    private(set) var planningMode: PlanningMode
    private(set) var dailyPlanProposal: DailyPlanProposal?
    private(set) var flareSuggestion: FlareSuggestion?
    private(set) var healthLensState: HealthLensState
    private(set) var guideExportEnvelopeText: String?
    private(set) var pendingGuideImportPreview: GuideImportPreview?
    var chatDraft: String

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
    private var foundationCheckIns: [FoundationCheckIn]
    private var userDefinedPillars: [UserDefinedPillar]
    private var pillarAssignments: [PillarAssignment]
    private var pillarCheckIns: [PillarCheckIn]
    private(set) var foundationCheckInResponsesByQuestionID: [String: Int]
    private var activeInterventions: [String]
    private var inputCheckOperationToken: Int
    private var inputDoseOperationToken: Int
    private var inputDoseSettingsOperationToken: Int
    private var inputActiveOperationToken: Int
    private var appleHealthConnectionOperationToken: Int
    private var morningOutcomeOperationToken: Int
    private var foundationCheckInOperationToken: Int
    private var graphDeactivationOperationToken: Int
    private var museSessionOperationToken: Int
    private var museOutcomeSaveOperationToken: Int
    private var museDiagnosticsPollingTask: Task<Void, Never>?
    private var museFitDiagnosticsPollingTask: Task<Void, Never>?
    private var projectionPublishTask: Task<Void, Never>?
    private var museRecordingStartedWithFitOverride: Bool
    private var progressQuestionSetState: ProgressQuestionSetState?
    private var gardenAliasOverrides: [GardenAliasOverride]
    private var plannerPreferencesState: PlannerPreferencesState
    private var habitPlannerState: HabitPlannerState
    private var planningMetadataByInterventionID: [String: HabitPlanningMetadata]
    private var ladderByInterventionID: [String: HabitLadderDefinition]
    private let interventionsCatalog: InterventionsCatalog
    private let planningPolicy: PlanningPolicy
    private var pendingGraphPatchEnvelope: GraphPatchEnvelope?
    private var pendingGuideImportEnvelope: GuideExportEnvelope?
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
    private let dailyPlanner: DailyPlanning
    private let flareDetectionService: FlareDetection
    private let planningMetadataResolver: HabitPlanningMetadataResolver
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
            graphData: CausalGraphData(nodes: [], edges: []),
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
        initialFoundationCheckIns: [FoundationCheckIn] = [],
        initialUserDefinedPillars: [UserDefinedPillar] = [],
        initialPillarAssignments: [PillarAssignment] = [],
        initialPillarCheckIns: [PillarCheckIn] = [],
        initialMorningQuestionnaire: MorningQuestionnaire? = nil,
        initialProgressQuestionSetState: ProgressQuestionSetState? = nil,
        initialPlannerPreferencesState: PlannerPreferencesState? = nil,
        initialHabitPlannerState: HabitPlannerState? = nil,
        initialHealthLensState: HealthLensState? = nil,
        initialGardenAliasOverrides: [GardenAliasOverride] = [],
        initialCustomCausalDiagram: CustomCausalDiagram? = nil,
        initialActiveInterventions: [String] = [],
        initialInterventionsCatalog: InterventionsCatalog = .empty,
        initialFoundationCatalog: FoundationCatalog? = nil,
        initialPlanningPolicy: PlanningPolicy? = nil,
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
        dailyPlanner: DailyPlanning? = nil,
        flareDetectionService: FlareDetection? = nil,
        planningMetadataResolver: HabitPlanningMetadataResolver? = nil,
        accessibilityAnnouncer: AccessibilityAnnouncer
    ) {
        let todayKey = Self.localDateKey(from: nowProvider())
        let seededGraphData = Self.seedHierarchyIfNeeded(graphData)
        let resolvedPlanningPolicy = initialPlanningPolicy ?? .default
        let resolvedPlanningMetadataResolver = planningMetadataResolver ?? HabitPlanningMetadataResolver(
            foundationCatalog: initialFoundationCatalog,
            interventionsCatalog: initialInterventionsCatalog,
            planningPolicy: resolvedPlanningPolicy
        )
        let resolvedInitialHealthLensState = Self.collapsedLensState(from: initialHealthLensState, nowProvider: nowProvider)
        let resolvedDailyPlanner = dailyPlanner ?? DailyPlanner()
        let resolvedFlareDetectionService = flareDetectionService ?? FlareDetectionService(policy: resolvedPlanningPolicy)
        let resolvedMorningOutcomeFields = Self.resolveMorningOutcomeFields(from: initialMorningQuestionnaire)
        let resolvedRequiredMorningOutcomeFields = Self.resolveRequiredMorningOutcomeFields(
            enabledFields: resolvedMorningOutcomeFields,
            questionnaire: initialMorningQuestionnaire
        )
        let resolvedMorningTrendMetrics = Self.resolveMorningTrendMetrics(from: resolvedMorningOutcomeFields)
        let resolvedPlannerPreferencesState = initialPlannerPreferencesState ?? PlannerPreferencesState(
            defaultAvailableMinutes: resolvedPlanningPolicy.defaultAvailableMinutes,
            modeOverride: nil,
            flareSensitivity: .balanced,
            updatedAt: Self.timestamp(from: nowProvider())
        )
        let initialTimelineState = resolvedPlannerPreferencesState.dailyTimeBudgetState
            ?? DailyTimeBudgetState.from(
                availableMinutes: resolvedPlannerPreferencesState.defaultAvailableMinutes,
                updatedAt: Self.timestamp(from: nowProvider())
            )
        let timelineMinutes = initialTimelineState.availableMinutes
        let resolvedPlannerAvailableMinutes = max(
            0,
            timelineMinutes > 0 ? timelineMinutes : resolvedPlannerPreferencesState.defaultAvailableMinutes
        )
        let resolvedPlanningMode = resolvedPlannerPreferencesState.modeOverride ?? .baseline

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
        graphCheckpointSummaries = []
        progressQuestionProposal = nil
        isProgressQuestionProposalPresented = false
        plannerPreferencesState = resolvedPlannerPreferencesState
        plannerTimeBudgetState = initialTimelineState
        plannerAvailableMinutes = resolvedPlannerAvailableMinutes
        planningMode = resolvedPlanningMode
        healthLensState = resolvedInitialHealthLensState
        dailyPlanProposal = nil
        flareSuggestion = nil
        guideExportEnvelopeText = nil
        pendingGuideImportPreview = nil
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
        foundationCheckIns = initialFoundationCheckIns
        userDefinedPillars = initialUserDefinedPillars
        pillarAssignments = initialPillarAssignments
        pillarCheckIns = initialPillarCheckIns
        foundationCheckInResponsesByQuestionID = Self.foundationResponses(
            for: todayKey,
            foundationCheckIns: initialFoundationCheckIns,
            pillarCheckIns: initialPillarCheckIns
        )
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
        foundationCheckInOperationToken = 0
        graphDeactivationOperationToken = 0
        museSessionOperationToken = 0
        museOutcomeSaveOperationToken = 0
        museDiagnosticsPollingTask = nil
        museFitDiagnosticsPollingTask = nil
        projectionPublishTask = nil
        museRecordingStartedWithFitOverride = false
        progressQuestionSetState = initialProgressQuestionSetState
        gardenAliasOverrides = initialGardenAliasOverrides
        habitPlannerState = initialHabitPlannerState ?? HabitPlannerState(
            entriesByInterventionID: [:],
            updatedAt: Self.timestamp(from: nowProvider())
        )
        interventionsCatalog = initialInterventionsCatalog
        planningPolicy = resolvedPlanningPolicy
        self.planningMetadataResolver = resolvedPlanningMetadataResolver
        let initialPlanningMetadataByInterventionID = resolvedPlanningMetadataResolver.metadataByInterventionID(
            for: snapshot.inputs
        )
        planningMetadataByInterventionID = initialPlanningMetadataByInterventionID
        ladderByInterventionID = resolvedPlanningMetadataResolver.ladderByInterventionID(
            metadataByInterventionID: initialPlanningMetadataByInterventionID
        )
        pendingGraphPatchEnvelope = nil
        pendingGuideImportEnvelope = nil

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
        self.dailyPlanner = resolvedDailyPlanner
        self.flareDetectionService = resolvedFlareDetectionService
        self.accessibilityAnnouncer = accessibilityAnnouncer

        Task {
            await publishGraphProjections()
        }
    }

    private static func collapsedLensState(
        from savedState: HealthLensState?,
        nowProvider: () -> Date
    ) -> HealthLensState {
        let startupPosition = LensControlPosition.midRight

        guard let savedState else {
            return HealthLensState(
                mode: .all,
                pillarSelection: .all,
                updatedAt: Self.timestamp(from: nowProvider()),
                controlState: LensControlState(
                    position: startupPosition,
                    isExpanded: false
                )
            )
        }

        return HealthLensState(
            mode: savedState.mode,
            pillarSelection: savedState.pillarSelection,
            updatedAt: savedState.updatedAt,
            controlState: LensControlState(
                position: startupPosition,
                isExpanded: false
            )
        )
    }

    func openProfileSheet() {
        isProfileSheetPresented = true
    }

    var morningStateHistory: [MorningState] {
        morningStates
    }

    var morningCheckInFields: [MorningOutcomeField] {
        let questionFields = questionDrivenMorningOutcomeFields()
        if questionFields.isEmpty {
            return configuredMorningOutcomeFields
        }
        return questionFields
    }

    var requiredMorningCheckInFields: [MorningOutcomeField] {
        let questionFields = questionDrivenMorningOutcomeFields()
        if questionFields.isEmpty {
            return requiredMorningOutcomeFields
        }
        return questionFields
    }

    var morningTrendMetricOptions: [MorningTrendMetric] {
        let questionFields = questionDrivenMorningOutcomeFields()
        if questionFields.isEmpty {
            return configuredMorningTrendMetrics
        }
        return Self.resolveMorningTrendMetrics(from: questionFields)
    }

    var foundationCheckInQuestions: [GraphDerivedProgressQuestion] {
        let questionByID = Dictionary(uniqueKeysWithValues: resolvedProgressQuestions().map { ($0.id, $0) })
        return activePillarsForProgress.map { pillar in
            let questionID = pillarQuestionID(for: pillar.id)
            if let resolved = questionByID[questionID] {
                return resolved
            }
            return defaultPillarQuestion(for: pillar)
        }
    }

    var foundationRequiredQuestionIDs: [String] {
        activePillarsForProgress.map { pillar in
            pillarQuestionID(for: pillar.id)
        }
    }

    var foundationCheckInNightID: String {
        morningOutcomeSelection.nightID
    }

    var foundationCheckInIsComplete: Bool {
        !foundationRequiredQuestionIDs.contains { questionID in
            foundationCheckInResponsesByQuestionID[questionID] == nil
        }
    }

    private func questionDrivenMorningOutcomeFields() -> [MorningOutcomeField] {
        let questions = resolvedProgressQuestions()
        if questions.isEmpty {
            return []
        }

        let mapped = questions.compactMap { question in
            Self.morningOutcomeField(fromProgressQuestionID: question.id)
        }
        return Self.deduplicatedMorningOutcomeFields(mapped)
    }

    private func resolvedProgressQuestions() -> [GraphDerivedProgressQuestion] {
        if let proposal = progressQuestionProposal {
            return proposal.questions
        }

        let activeQuestions = progressQuestionSetState?.activeQuestions ?? []
        if !activeQuestions.isEmpty {
            return activeQuestions
        }

        return []
    }

    var projectedInputs: [InputStatus] {
        graphProjectionHub.habits.inputs.filter { input in
            matchesHealthLens(input: input)
        }
    }

    var projectedSituationGraphData: CausalGraphData {
        guard !isGlobalLensAllSelected else {
            return graphData
        }

        let selectedPillarIDs = selectedLensPillarIDs()
        guard !selectedPillarIDs.isEmpty else {
            return CausalGraphData(nodes: [], edges: [])
        }
        let ownedNodeIDsByPillarID = ownedGraphNodeIDsByPillarID()
        let ownedEdgeIDsByPillarID = ownedGraphEdgeIDsByPillarID()
        let sourceNodeIDs = selectedPillarIDs.reduce(into: Set<String>()) { result, pillarID in
            result.formUnion(ownedNodeIDsByPillarID[pillarID, default: []])
        }
        let sourceEdgeIDs = selectedPillarIDs.reduce(into: Set<String>()) { result, pillarID in
            result.formUnion(ownedEdgeIDsByPillarID[pillarID, default: []])
        }

        if sourceNodeIDs.isEmpty {
            return CausalGraphData(nodes: [], edges: [])
        }

        let edges = resolvedGraphEdgeRows().compactMap { row -> GraphEdgeElement? in
            guard sourceEdgeIDs.contains(row.id) else {
                return nil
            }
            guard sourceNodeIDs.contains(row.data.source), sourceNodeIDs.contains(row.data.target) else {
                return nil
            }
            return GraphEdgeElement(data: row.data)
        }
        let connectedNodeIDs = Set(edges.flatMap { edge in
            [edge.data.source, edge.data.target]
        }).union(sourceNodeIDs)
        let nodes = graphData.nodes.filter { node in
            connectedNodeIDs.contains(node.data.id) && sourceNodeIDs.contains(node.data.id)
        }

        return CausalGraphData(nodes: nodes, edges: edges)
    }

    var projectedSituationGraphIsLensFilteredEmpty: Bool {
        !isGlobalLensAllSelected && projectedSituationGraphData.nodes.isEmpty
    }

    var projectedSituationGraphEmptyMessage: String {
        "No mapped nodes yet for \(projectedHealthLensLabel)."
    }

    var projectedGuideGraphVersion: String? {
        graphProjectionHub.guide.graphVersion
    }

    var projectedGuideExportEnvelopeText: String? {
        guideExportEnvelopeText
    }

    var projectedGuideImportPreview: GuideImportPreview? {
        pendingGuideImportPreview
    }

    var projectedGraphCheckpointSummaries: [GraphCheckpointSummary] {
        graphCheckpointSummaries
    }

    var projectedPlanningMetadataByInterventionID: [String: HabitPlanningMetadata] {
        planningMetadataByInterventionID
    }

    var projectedDailyPlanProposal: DailyPlanProposal? {
        dailyPlanProposal
    }

    var projectedPlannedInterventionIDs: Set<String> {
        Set(dailyPlanProposal?.actions.map(\.interventionID) ?? [])
    }

    var projectedFlareSuggestion: FlareSuggestion? {
        flareSuggestion
    }

    var projectedPlannerTimeBudgetState: DailyTimeBudgetState {
        plannerTimeBudgetState
    }

    var projectedLensControlState: LensControlState {
        healthLensState.controlState
    }

    var projectedHealthLensLabel: String {
        if healthLensState.mode == .all || healthLensState.pillarSelection.isAllSelected {
            return HealthLensMode.all.displayName
        }

        let selectedPillars = healthLensState.selectedPillarIDs
        if selectedPillars.isEmpty {
            return "None"
        }

        if selectedPillars.count == 1, let selectedPillar = selectedPillars.first {
            return titleForPillarID(selectedPillar.id)
        }

        return "\(selectedPillars.count) pillars"
    }

    var projectedHealthLensMode: HealthLensMode {
        healthLensState.mode
    }

    var projectedHealthLensSelection: PillarLensSelection {
        healthLensState.pillarSelection
    }

    var projectedSelectedHealthLensPillars: [HealthPillar] {
        healthLensState.selectedPillarIDs
    }

    var projectedHealthLensPreset: HealthLensPreset {
        healthLensState.preset
    }

    var projectedHealthLensPillar: HealthPillar? {
        healthLensState.selectedPillar
    }

    var projectedHealthLensPillars: [HealthPillarDefinition] {
        projectedCoreHealthLensPillars + projectedUserDefinedHealthLensPillars
    }

    var projectedCoreHealthLensPillars: [HealthPillarDefinition] {
        planningPolicy.orderedPillars
    }

    var projectedUserDefinedHealthLensPillars: [HealthPillarDefinition] {
        userDefinedPillars
            .filter { !$0.isArchived }
            .sorted { left, right in
                if left.createdAt != right.createdAt {
                    return left.createdAt < right.createdAt
                }
                return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
            }
            .enumerated()
            .map { offset, pillar in
                HealthPillarDefinition(
                    id: HealthPillar(id: pillar.id),
                    title: pillar.title,
                    rank: planningPolicy.orderedPillars.count + offset + 1
                )
            }
    }

    var projectedPillarAssignments: [PillarAssignment] {
        pillarAssignments
    }

    var projectedUserDefinedPillars: [UserDefinedPillar] {
        userDefinedPillars
    }

    var projectedProgressMorningStatesForCharts: [MorningState] {
        morningStatesFilteredForCurrentLens
    }

    var projectedProgressNightOutcomesForCharts: [NightOutcome] {
        nightOutcomesFilteredForCurrentLens
    }

    var projectedProgressExcludedChartsNote: String? {
        guard !isGlobalLensAllSelected else {
            return nil
        }

        let unscopedMorning = morningStates.filter { $0.graphAssociation == nil }.count
        let unscopedNight = nightOutcomes.filter { $0.graphAssociation == nil }.count
        let outOfScopeMorning = morningStates.filter {
            $0.graphAssociation != nil && !graphAssociationMatchesLens($0.graphAssociation)
        }.count
        let outOfScopeNight = nightOutcomes.filter {
            $0.graphAssociation != nil && !graphAssociationMatchesLens($0.graphAssociation)
        }.count
        let excludedTotal = unscopedMorning + unscopedNight + outOfScopeMorning + outOfScopeNight
        guard excludedTotal > 0 else {
            return nil
        }

        return "\(excludedTotal) chart points were excluded (\(unscopedMorning + unscopedNight) unscoped, \(outOfScopeMorning + outOfScopeNight) outside lens)."
    }

    var projectedHabitRungStatusByInterventionID: [String: HabitRungStatus] {
        var result: [String: HabitRungStatus] = [:]

        for input in snapshot.inputs {
            guard let ladder = ladderByInterventionID[input.id], !ladder.rungs.isEmpty else {
                continue
            }
            let entry = habitPlannerState.entriesByInterventionID[input.id] ?? .empty
            let currentIndex = min(max(entry.currentRungIndex, 0), ladder.rungs.count - 1)
            let current = ladder.rungs[currentIndex]
            let target = ladder.rungs[0]
            let higherRungs = Array(ladder.rungs.prefix(currentIndex))
            result[input.id] = HabitRungStatus(
                interventionID: input.id,
                currentRungID: current.id,
                currentRungTitle: current.title,
                targetRungID: target.id,
                targetRungTitle: target.title,
                canReportHigherCompletion: currentIndex > 0,
                higherRungs: higherRungs
            )
        }

        return result
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
            activeQuestions: proposal.questions,
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
            activeQuestions: current.activeQuestions,
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
            exportGuideSections(Set([.graph, .aliases]))
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

    func exportGuideSections(_ sections: Set<GuideTransferSection>) {
        guard mode == .explore else { return }
        let orderedSections = GuideTransferSection.allCases.filter { sections.contains($0) }
        guard !orderedSections.isEmpty else {
            exploreFeedback = "Select at least one section to export."
            announce(exploreFeedback)
            return
        }

        Task {
            do {
                let diagram = await graphKernel.currentDiagram()
                let aliases = await graphKernel.currentAliasOverrides()
                let envelope = GuideExportEnvelope(
                    schemaVersion: "guide-transfer.v1",
                    sections: orderedSections,
                    graph: orderedSections.contains(.graph)
                        ? GuideGraphTransferPayload(
                            graphVersion: diagram.graphVersion,
                            baseGraphVersion: diagram.baseGraphVersion,
                            lastModified: diagram.lastModified,
                            graphData: diagram.graphData
                        )
                        : nil,
                    aliases: orderedSections.contains(.aliases) ? aliases : nil,
                    planner: orderedSections.contains(.planner)
                        ? GuidePlannerTransferPayload(
                            plannerPreferencesState: plannerPreferencesState,
                            habitPlannerState: habitPlannerState,
                            healthLensState: healthLensState
                        )
                        : nil
                )
                let exportText = try graphPatchCodec.encodeGuideExportEnvelope(envelope)
                guideExportEnvelopeText = exportText
                exploreFeedback = "Guide export ready. Characters: \(exportText.count)."
                announce(exploreFeedback)
            } catch {
                exploreFeedback = "Guide export failed."
                announce(exploreFeedback)
            }
        }
    }

    func previewGuideImportPayload(_ text: String) {
        guard mode == .explore else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingGuideImportEnvelope = nil
            pendingGuideImportPreview = GuideImportPreview(
                sections: [],
                summaryLines: [],
                validationError: "Import payload is empty."
            )
            return
        }

        do {
            let envelope = try graphPatchCodec.decodeGuideExportEnvelope(from: trimmed)
            let preview = guideImportPreview(for: envelope)
            pendingGuideImportPreview = preview
            if preview.isValid {
                pendingGuideImportEnvelope = envelope
                exploreFeedback = "Guide import preview ready. Apply when ready."
            } else {
                pendingGuideImportEnvelope = nil
                exploreFeedback = preview.validationError ?? "Guide import preview failed."
            }
            announce(exploreFeedback)
        } catch {
            pendingGuideImportEnvelope = nil
            let errorText = graphPatchCodec.decodeErrorMessage(for: error)
            pendingGuideImportPreview = GuideImportPreview(
                sections: [],
                summaryLines: [],
                validationError: errorText
            )
            exploreFeedback = "Import parse failed: \(errorText)"
            announce(exploreFeedback)
        }
    }

    func applyPendingGuideImportPayload() {
        guard mode == .explore else { return }
        guard let envelope = pendingGuideImportEnvelope else {
            exploreFeedback = "No validated import payload. Preview first."
            announce(exploreFeedback)
            return
        }
        guard pendingGuideImportPreview?.isValid == true else {
            exploreFeedback = "Resolve import validation issues before applying."
            announce(exploreFeedback)
            return
        }

        Task {
            let previousDiagram = await graphKernel.currentDiagram()
            let previousAliases = await graphKernel.currentAliasOverrides()
            let previousPlannerPreferences = plannerPreferencesState
            let previousPlannerState = habitPlannerState
            let previousLensState = healthLensState
            let previousPlanningMode = planningMode
            let previousTimeBudgetState = plannerTimeBudgetState
            let previousAvailableMinutes = plannerAvailableMinutes

            var nextDiagram = previousDiagram
            var nextAliases = previousAliases
            var nextPlannerPreferences = plannerPreferencesState
            var nextPlannerState = habitPlannerState
            var nextLensState = healthLensState

            let sections = GuideTransferSection.allCases.filter { envelope.sections.contains($0) }
            for section in sections {
                switch section {
                case .graph:
                    guard let payload = envelope.graph else { continue }
                    nextDiagram = CustomCausalDiagram(
                        graphData: payload.graphData,
                        lastModified: payload.lastModified ?? DateKeying.timestamp(from: nowProvider()),
                        graphVersion: payload.graphVersion,
                        baseGraphVersion: payload.baseGraphVersion
                    )
                case .aliases:
                    guard let aliases = envelope.aliases else { continue }
                    nextAliases = aliases.sorted { $0.signature < $1.signature }
                case .planner:
                    guard let payload = envelope.planner else { continue }
                    nextPlannerPreferences = payload.plannerPreferencesState
                    nextPlannerState = payload.habitPlannerState
                    nextLensState = payload.healthLensState
                }
            }

            let graphChanged = nextDiagram != previousDiagram
            let aliasesChanged = nextAliases != previousAliases
            let plannerChanged =
                nextPlannerPreferences != previousPlannerPreferences
                || nextPlannerState != previousPlannerState
                || nextLensState != previousLensState

            if !graphChanged, !aliasesChanged, !plannerChanged {
                pendingGuideImportEnvelope = nil
                pendingGuideImportPreview = nil
                exploreFeedback = "Import contained no changes."
                announce(exploreFeedback)
                return
            }

            if graphChanged || aliasesChanged {
                await graphKernel.replace(
                    diagram: nextDiagram,
                    aliasOverrides: nextAliases,
                    recordCheckpoint: true
                )
                graphData = nextDiagram.graphData
                gardenAliasOverrides = nextAliases
            }

            if plannerChanged {
                plannerPreferencesState = nextPlannerPreferences
                habitPlannerState = nextPlannerState
                healthLensState = nextLensState
                plannerTimeBudgetState = nextPlannerPreferences.dailyTimeBudgetState
                    ?? DailyTimeBudgetState.from(
                        availableMinutes: nextPlannerPreferences.defaultAvailableMinutes,
                        updatedAt: Self.timestamp(from: nowProvider())
                    )
                plannerAvailableMinutes = plannerTimeBudgetState.availableMinutes
                planningMode = nextPlannerPreferences.modeOverride ?? planningMode
            }

            refreshPlanningState()
            await publishGraphProjections()

            let patch = UserDataPatch(
                experienceFlow: nil,
                dailyCheckIns: nil,
                dailyDoseProgress: nil,
                interventionCompletionEvents: nil,
                interventionDoseSettings: nil,
                appleHealthConnections: nil,
                nightOutcomes: nil,
                morningStates: nil,
                activeInterventions: nil,
                hiddenInterventions: nil,
                customCausalDiagram: graphChanged ? nextDiagram : nil,
                wakeDaySleepAttributionMigrated: nil,
                progressQuestionSetState: nil,
                gardenAliasOverrides: aliasesChanged ? nextAliases : nil,
                plannerPreferencesState: plannerChanged ? nextPlannerPreferences : nil,
                habitPlannerState: plannerChanged ? nextPlannerState : nil,
                healthLensState: plannerChanged ? nextLensState : nil
            )

            do {
                try await persistPatch(patch)
                pendingGuideImportEnvelope = nil
                pendingGuideImportPreview = nil
                exploreFeedback = "Guide import applied."
                announce(exploreFeedback)
            } catch {
                plannerPreferencesState = previousPlannerPreferences
                habitPlannerState = previousPlannerState
                healthLensState = previousLensState
                planningMode = previousPlanningMode
                plannerTimeBudgetState = previousTimeBudgetState
                plannerAvailableMinutes = previousAvailableMinutes
                graphData = previousDiagram.graphData
                gardenAliasOverrides = previousAliases
                await graphKernel.replace(
                    diagram: previousDiagram,
                    aliasOverrides: previousAliases,
                    recordCheckpoint: false
                )
                refreshPlanningState()
                await publishGraphProjections()
                exploreFeedback = "Guide import failed and was reverted."
                announce(exploreFeedback)
            }
        }
    }

    func clearPendingGuideImportPreview() {
        pendingGuideImportEnvelope = nil
        pendingGuideImportPreview = nil
    }

    private func guideImportPreview(for envelope: GuideExportEnvelope) -> GuideImportPreview {
        let sections = GuideTransferSection.allCases.filter { envelope.sections.contains($0) }
        guard !sections.isEmpty else {
            return GuideImportPreview(
                sections: [],
                summaryLines: [],
                validationError: "Envelope has no selected sections."
            )
        }

        var summaryLines: [String] = []
        for section in sections {
            switch section {
            case .graph:
                guard let graph = envelope.graph else {
                    return GuideImportPreview(
                        sections: sections,
                        summaryLines: summaryLines,
                        validationError: "Graph section selected but graph payload is missing."
                    )
                }
                summaryLines.append("Graph: \(graph.graphData.nodes.count) nodes, \(graph.graphData.edges.count) edges.")
            case .aliases:
                guard let aliases = envelope.aliases else {
                    return GuideImportPreview(
                        sections: sections,
                        summaryLines: summaryLines,
                        validationError: "Aliases section selected but alias payload is missing."
                    )
                }
                summaryLines.append("Aliases: \(aliases.count) entries.")
            case .planner:
                guard let planner = envelope.planner else {
                    return GuideImportPreview(
                        sections: sections,
                        summaryLines: summaryLines,
                        validationError: "Planner section selected but planner payload is missing."
                    )
                }
                summaryLines.append("Planner: \(planner.plannerPreferencesState.defaultAvailableMinutes) min default, mode \(planner.plannerPreferencesState.modeOverride?.rawValue ?? "none").")
            }
        }

        return GuideImportPreview(
            sections: sections,
            summaryLines: summaryLines,
            validationError: nil
        )
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
        graphCheckpointSummaries = checkpoints.map { checkpoint in
            GraphCheckpointSummary(
                graphVersion: checkpoint.graphVersion,
                createdAt: checkpoint.createdAt,
                nodeCount: checkpoint.diagram.graphData.nodes.count,
                edgeCount: checkpoint.diagram.graphData.edges.count
            )
        }
        refreshProgressQuestionProposalState(for: diagram.graphVersion)
        refreshPlanningState()
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
            if let pendingProposal = existingState.pendingProposal,
               pendingProposal.sourceGraphVersion == graphVersion,
               pendingProposal.proposedQuestionSetVersion != existingState.activeQuestionSetVersion {
                progressQuestionProposal = pendingProposal
                return
            }

            progressQuestionProposal = nil
            isProgressQuestionProposalPresented = false
            if existingState.pendingProposal != nil {
                let nextState = ProgressQuestionSetState(
                    activeQuestionSetVersion: existingState.activeQuestionSetVersion,
                    activeSourceGraphVersion: existingState.activeSourceGraphVersion,
                    activeQuestions: existingState.activeQuestions,
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
            activeQuestions: existingState.activeQuestions,
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
        let activeSourceGraphVersion = progressQuestionSetState?.activeSourceGraphVersion
        let activeQuestionSetVersion = progressQuestionSetState?.activeQuestionSetVersion
        if proposal.sourceGraphVersion == activeSourceGraphVersion,
           proposal.proposedQuestionSetVersion == activeQuestionSetVersion {
            return
        }
        isProgressQuestionProposalPresented = true
    }

    private func baselineProgressQuestionSetState(for graphVersion: String) -> ProgressQuestionSetState {
        ProgressQuestionSetState(
            activeQuestionSetVersion: "questions-\(graphVersion)",
            activeSourceGraphVersion: graphVersion,
            activeQuestions: defaultActiveProgressQuestions(),
            declinedGraphVersions: [],
            pendingProposal: nil,
            updatedAt: Self.timestamp(from: nowProvider())
        )
    }

    private func defaultActiveProgressQuestions() -> [GraphDerivedProgressQuestion] {
        var questions = configuredMorningOutcomeFields.map { field in
            GraphDerivedProgressQuestion(
                id: Self.progressQuestionID(from: field),
                title: field.displayTitle,
                sourceNodeIDs: [],
                sourceEdgeIDs: []
            )
        }
        questions.append(contentsOf: activePillarsForProgress.map(defaultPillarQuestion(for:)))
        return Self.deduplicatedProgressQuestions(questions)
    }

    private func buildProgressQuestionSetProposal(for graphVersion: String) -> ProgressQuestionSetProposal {
        progressQuestionProposalBuilder.build(
            graphData: graphData,
            inputs: snapshot.inputs.filter(\.isActive),
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            policy: planningPolicy,
            mode: planningMode,
            graphVersion: graphVersion,
            createdAt: Self.timestamp(from: nowProvider())
        )
    }

    func setPlannerAvailableMinutes(_ minutes: Int) {
        let clamped = min(16 * 60, max(0, minutes))
        guard clamped != plannerAvailableMinutes else {
            return
        }

        let timestamp = Self.timestamp(from: nowProvider())
        plannerTimeBudgetState = DailyTimeBudgetState.from(
            availableMinutes: clamped,
            updatedAt: timestamp,
            window: plannerTimeBudgetState.timelineWindow
        )
        plannerAvailableMinutes = clamped
        plannerPreferencesState = PlannerPreferencesState(
            defaultAvailableMinutes: clamped,
            modeOverride: plannerPreferencesState.modeOverride,
            flareSensitivity: plannerPreferencesState.flareSensitivity,
            updatedAt: timestamp,
            dailyTimeBudgetState: plannerTimeBudgetState
        )
        refreshPlanningState()
        persistPlannerPreferencesState()
    }

    func setPlannerTimeBudgetState(_ state: DailyTimeBudgetState) {
        let timestamp = Self.timestamp(from: nowProvider())
        let nextState = DailyTimeBudgetState(
            timelineWindow: state.timelineWindow,
            selectedSlotStartMinutes: state.selectedSlotStartMinutes,
            updatedAt: timestamp
        )
        plannerTimeBudgetState = nextState
        plannerAvailableMinutes = nextState.availableMinutes
        plannerPreferencesState = PlannerPreferencesState(
            defaultAvailableMinutes: nextState.availableMinutes,
            modeOverride: plannerPreferencesState.modeOverride,
            flareSensitivity: plannerPreferencesState.flareSensitivity,
            updatedAt: timestamp,
            dailyTimeBudgetState: nextState
        )
        refreshPlanningState()
        persistPlannerPreferencesState()
    }

    func setLensControlExpanded(_ isExpanded: Bool) {
        guard healthLensState.controlState.isExpanded != isExpanded else {
            return
        }
        healthLensState = HealthLensState(
            mode: healthLensState.mode,
            pillarSelection: healthLensState.pillarSelection,
            updatedAt: Self.timestamp(from: nowProvider()),
            controlState: LensControlState(
                position: healthLensState.controlState.position,
                isExpanded: isExpanded
            )
        )
        persistHealthLensState()
    }

    private func persistPlannerPreferencesState() {
        Task {
            do {
                try await persistPatch(.plannerPreferencesState(plannerPreferencesState))
            } catch {
            }
        }
    }

    func setHealthLensPreset(_ preset: HealthLensPreset) {
        switch preset {
        case .all, .acute, .foundation:
            selectAllHealthLensPillars()
        case .pillar:
            if !healthLensState.selectedPillarIDs.isEmpty && healthLensState.mode == .pillars {
                return
            }
            if let firstPillar = projectedHealthLensPillars.first?.id {
                setHealthLensPillar(firstPillar)
                return
            }
            clearHealthLensPillars()
        }
    }

    func setHealthLensPillar(_ pillar: HealthPillar) {
        guard healthLensState.mode != .pillars
            || healthLensState.pillarSelection.isAllSelected
            || healthLensState.selectedPillarIDs != [pillar] else {
            return
        }

        healthLensState = HealthLensState(
            mode: .pillars,
            pillarSelection: PillarLensSelection(
                selectedPillarIDs: [pillar],
                isAllSelected: false
            ),
            updatedAt: Self.timestamp(from: nowProvider()),
            controlState: healthLensState.controlState
        )
        scheduleProjectionPublish()
        persistHealthLensState()
    }

    func selectAllHealthLensPillars() {
        guard !isGlobalLensAllSelected else {
            return
        }

        healthLensState = HealthLensState(
            mode: .all,
            pillarSelection: .all,
            updatedAt: Self.timestamp(from: nowProvider()),
            controlState: healthLensState.controlState
        )
        scheduleProjectionPublish()
        persistHealthLensState()
    }

    func clearHealthLensPillars() {
        if healthLensState.mode == .pillars
            && !healthLensState.pillarSelection.isAllSelected
            && healthLensState.selectedPillarIDs.isEmpty {
            return
        }

        healthLensState = HealthLensState(
            mode: .pillars,
            pillarSelection: PillarLensSelection(
                selectedPillarIDs: [],
                isAllSelected: false
            ),
            updatedAt: Self.timestamp(from: nowProvider()),
            controlState: healthLensState.controlState
        )
        scheduleProjectionPublish()
        persistHealthLensState()
    }

    func toggleHealthLensPillar(_ pillar: HealthPillar) {
        var selectedPillarIDs = Set(healthLensState.selectedPillarIDs.map(\.id))
        if selectedPillarIDs.contains(pillar.id) {
            selectedPillarIDs.remove(pillar.id)
        } else {
            selectedPillarIDs.insert(pillar.id)
        }

        let orderedSelected = projectedHealthLensPillars
            .map(\.id)
            .filter { selectedPillarIDs.contains($0.id) }
        healthLensState = HealthLensState(
            mode: .pillars,
            pillarSelection: PillarLensSelection(
                selectedPillarIDs: orderedSelected,
                isAllSelected: false
            ),
            updatedAt: Self.timestamp(from: nowProvider()),
            controlState: healthLensState.controlState
        )
        scheduleProjectionPublish()
        persistHealthLensState()
    }

    func createUserDefinedPillar(templateID: String, title: String) {
        guard mode == .explore else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let nowTimestamp = Self.timestamp(from: nowProvider())
        let baseIdentifier = Self.slug(from: trimmedTitle)
        let existingIDs = Set(userDefinedPillars.map(\.id))
        var resolvedID = baseIdentifier
        var suffix = 2
        while existingIDs.contains(resolvedID) {
            resolvedID = "\(baseIdentifier)-\(suffix)"
            suffix += 1
        }

        let nextPillar = UserDefinedPillar(
            id: resolvedID,
            title: trimmedTitle,
            templateId: templateID,
            createdAt: nowTimestamp,
            updatedAt: nowTimestamp,
            isArchived: false
        )
        userDefinedPillars.append(nextPillar)
        userDefinedPillars.sort { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
        }
        pillarAssignments.append(
            PillarAssignment(
                pillarId: resolvedID,
                graphNodeIds: [],
                graphEdgeIds: [],
                interventionIds: [],
                questionId: "pillar.\(resolvedID)"
            )
        )
        refreshPlanningState()
        persistPillarConfiguration()
    }

    func renameUserDefinedPillar(pillarID: String, title: String) {
        guard mode == .explore else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        guard let index = userDefinedPillars.firstIndex(where: { $0.id == pillarID }) else {
            return
        }
        let existing = userDefinedPillars[index]
        guard existing.title != trimmedTitle else {
            return
        }

        userDefinedPillars[index] = UserDefinedPillar(
            id: existing.id,
            title: trimmedTitle,
            templateId: existing.templateId,
            createdAt: existing.createdAt,
            updatedAt: Self.timestamp(from: nowProvider()),
            isArchived: existing.isArchived
        )
        refreshPlanningState()
        persistPillarConfiguration()
    }

    func setUserDefinedPillarArchived(pillarID: String, isArchived: Bool) {
        guard mode == .explore else { return }
        guard let index = userDefinedPillars.firstIndex(where: { $0.id == pillarID }) else {
            return
        }
        let existing = userDefinedPillars[index]
        guard existing.isArchived != isArchived else {
            return
        }

        userDefinedPillars[index] = UserDefinedPillar(
            id: existing.id,
            title: existing.title,
            templateId: existing.templateId,
            createdAt: existing.createdAt,
            updatedAt: Self.timestamp(from: nowProvider()),
            isArchived: isArchived
        )

        if isArchived {
            let selectedIDs = Set(healthLensState.selectedPillarIDs.map(\.id))
            if selectedIDs.contains(pillarID) {
                let filtered = healthLensState.selectedPillarIDs.filter { $0.id != pillarID }
                healthLensState = HealthLensState(
                    mode: .pillars,
                    pillarSelection: PillarLensSelection(
                        selectedPillarIDs: filtered,
                        isAllSelected: false
                    ),
                    updatedAt: Self.timestamp(from: nowProvider()),
                    controlState: healthLensState.controlState
                )
            }
        }

        refreshPlanningState()
        persistPillarConfiguration()
        persistHealthLensState()
    }

    private func persistPillarConfiguration() {
        Task {
            do {
                let patch = UserDataPatch(
                    experienceFlow: nil,
                    dailyCheckIns: nil,
                    dailyDoseProgress: nil,
                    interventionCompletionEvents: nil,
                    interventionDoseSettings: nil,
                    appleHealthConnections: nil,
                    morningStates: nil,
                    userDefinedPillars: userDefinedPillars,
                    pillarAssignments: pillarAssignments,
                    activeInterventions: nil,
                    hiddenInterventions: nil
                )
                try await persistPatch(patch)
            } catch {
            }
        }
    }

    func acceptFlareSuggestion() {
        guard let flareSuggestion else {
            return
        }
        switch flareSuggestion.direction {
        case .enterFlare:
            planningMode = .flare
        case .exitFlare:
            planningMode = .baseline
        }
        self.flareSuggestion = nil
        plannerPreferencesState = PlannerPreferencesState(
            defaultAvailableMinutes: plannerAvailableMinutes,
            modeOverride: planningMode,
            flareSensitivity: plannerPreferencesState.flareSensitivity,
            updatedAt: Self.timestamp(from: nowProvider()),
            dailyTimeBudgetState: plannerTimeBudgetState
        )
        refreshPlanningState()
        persistPlannerPreferencesState()
    }

    func dismissFlareSuggestion() {
        flareSuggestion = nil
    }

    private func persistHealthLensState() {
        Task {
            do {
                let patch = UserDataPatch(
                    experienceFlow: nil,
                    dailyCheckIns: nil,
                    dailyDoseProgress: nil,
                    interventionCompletionEvents: nil,
                    interventionDoseSettings: nil,
                    appleHealthConnections: nil,
                    morningStates: nil,
                    activeInterventions: nil,
                    hiddenInterventions: nil,
                    healthLensState: healthLensState,
                    globalLensSelection: healthLensState
                )
                try await persistPatch(patch)
            } catch {
            }
        }
    }

    private func refreshPlanningState() {
        planningMetadataByInterventionID = planningMetadataResolver.metadataByInterventionID(for: snapshot.inputs)
        ladderByInterventionID = planningMetadataResolver.ladderByInterventionID(
            metadataByInterventionID: planningMetadataByInterventionID
        )

        let todayKey = Self.localDateKey(from: nowProvider())
        let context = DailyPlanningContext(
            availableMinutes: plannerAvailableMinutes,
            mode: planningMode,
            todayKey: todayKey,
            policy: planningPolicy,
            inputs: snapshot.inputs,
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            ladderByInterventionID: ladderByInterventionID,
            plannerState: habitPlannerState,
            morningStates: morningStates,
            nightOutcomes: nightOutcomes,
            selectedSlotStartMinutes: plannerTimeBudgetState.selectedSlotStartMinutes
        )
        let proposal = dailyPlanner.buildProposal(context: context)
        dailyPlanProposal = proposal
        habitPlannerState = proposal.nextPlannerState

        flareSuggestion = flareDetectionService.detectSuggestion(
            mode: planningMode,
            morningStates: morningStates,
            nightOutcomes: nightOutcomes,
            sensitivity: plannerPreferencesState.flareSensitivity
        )
    }

    private var healthLensNodeIDs: Set<String> {
        if isGlobalLensAllSelected {
            return Set(
                snapshot.inputs.compactMap { input in
                    input.graphNodeID ?? input.id
                }
            )
        }

        let selectedPillarIDs = selectedLensPillarIDs()
        if selectedPillarIDs.isEmpty {
            return []
        }

        let nodeIDsByPillarID = ownedGraphNodeIDsByPillarID()
        return selectedPillarIDs.reduce(into: Set<String>()) { result, pillarID in
            result.formUnion(nodeIDsByPillarID[pillarID, default: []])
        }
    }

    private var morningStatesFilteredForCurrentLens: [MorningState] {
        guard !isGlobalLensAllSelected else {
            return morningStates
        }
        return morningStates.filter { state in
            graphAssociationMatchesLens(state.graphAssociation)
        }
    }

    private var nightOutcomesFilteredForCurrentLens: [NightOutcome] {
        guard !isGlobalLensAllSelected else {
            return nightOutcomes
        }
        return nightOutcomes.filter { outcome in
            graphAssociationMatchesLens(outcome.graphAssociation)
        }
    }

    private func graphAssociationMatchesLens(_ association: GraphAssociationRef?) -> Bool {
        guard !isGlobalLensAllSelected else {
            return true
        }
        guard let association else {
            return false
        }

        let lensNodes = healthLensNodeIDs
        guard !lensNodes.isEmpty else {
            return false
        }

        return association.nodeIDs.contains { nodeID in
            lensNodes.contains(nodeID)
        }
    }

    private func matchesHealthLens(input: InputStatus) -> Bool {
        if isGlobalLensAllSelected {
            return true
        }

        let selectedPillarIDs = selectedLensPillarIDs()
        if selectedPillarIDs.isEmpty {
            return false
        }

        let inputPillarIDs = pillarIDs(for: input.id)
        if inputPillarIDs.isEmpty {
            return false
        }

        return !selectedPillarIDs.isDisjoint(with: inputPillarIDs)
    }

    private var isGlobalLensAllSelected: Bool {
        healthLensState.mode == .all || healthLensState.pillarSelection.isAllSelected
    }

    private func selectedLensPillarIDs() -> Set<String> {
        if isGlobalLensAllSelected {
            return Set(projectedHealthLensPillars.map { $0.id.id })
        }
        return Set(healthLensState.selectedPillarIDs.map(\.id))
    }

    private func titleForPillarID(_ pillarID: String) -> String {
        if let definition = projectedHealthLensPillars.first(where: { $0.id.id == pillarID }) {
            return definition.title
        }
        return HealthPillar(id: pillarID).displayName
    }

    private func pillarIDs(for interventionID: String) -> Set<String> {
        var pillarIDs = Set(
            planningMetadataByInterventionID[interventionID]?.pillars.map(\.id) ?? []
        )
        for assignment in pillarAssignments where assignment.interventionIds.contains(interventionID) {
            let pillarID = assignment.pillarId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pillarID.isEmpty {
                pillarIDs.insert(pillarID)
            }
        }
        return pillarIDs
    }

    private func resolvedGraphEdgeRows() -> [ResolvedGraphEdgeRow] {
        var duplicateCounterByBase: [String: Int] = [:]
        return graphData.edges.map { edge in
            let edgeType = edge.data.edgeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = edge.data.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let base = "edge:\(edge.data.source)|\(edge.data.target)|\(edgeType)|\(label)"
            let duplicateIndex = duplicateCounterByBase[base] ?? 0
            duplicateCounterByBase[base] = duplicateIndex + 1
            return ResolvedGraphEdgeRow(
                id: resolvedGraphEdgeID(edge: edge.data, duplicateIndex: duplicateIndex),
                data: edge.data
            )
        }
    }

    private func resolvedGraphEdgeID(edge: GraphEdgeData, duplicateIndex: Int) -> String {
        if let explicitID = edge.id?.trimmingCharacters(in: .whitespacesAndNewlines), !explicitID.isEmpty {
            return explicitID
        }

        let edgeType = edge.edgeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "edge:\(edge.source)|\(edge.target)|\(edgeType)|\(label)#\(duplicateIndex)"
    }

    private func ownedGraphNodeIDsByPillarID() -> [String: Set<String>] {
        let graphNodeIDSet = Set(graphData.nodes.map { $0.data.id })
        var nodeIDsByPillarID: [String: Set<String>] = [:]

        for node in graphData.nodes {
            for pillarID in node.data.pillarIds ?? [] where !pillarID.isEmpty {
                nodeIDsByPillarID[pillarID, default: []].insert(node.data.id)
            }
        }

        for input in snapshot.inputs {
            guard let graphNodeID = input.graphNodeID, graphNodeIDSet.contains(graphNodeID) else {
                continue
            }

            for pillarID in pillarIDs(for: input.id) {
                nodeIDsByPillarID[pillarID, default: []].insert(graphNodeID)
            }
        }

        for assignment in pillarAssignments {
            let pillarID = assignment.pillarId.trimmingCharacters(in: .whitespacesAndNewlines)
            if pillarID.isEmpty {
                continue
            }

            for nodeID in assignment.graphNodeIds where graphNodeIDSet.contains(nodeID) {
                nodeIDsByPillarID[pillarID, default: []].insert(nodeID)
            }

            for interventionID in assignment.interventionIds {
                guard let graphNodeID = snapshot.inputs.first(where: { $0.id == interventionID })?.graphNodeID else {
                    continue
                }
                guard graphNodeIDSet.contains(graphNodeID) else {
                    continue
                }
                nodeIDsByPillarID[pillarID, default: []].insert(graphNodeID)
            }
        }

        return nodeIDsByPillarID
    }

    private func ownedGraphEdgeIDsByPillarID() -> [String: Set<String>] {
        let resolvedEdges = resolvedGraphEdgeRows()
        let edgeByID = Dictionary(uniqueKeysWithValues: resolvedEdges.map { ($0.id, $0.data) })
        let nodeIDsByPillarID = ownedGraphNodeIDsByPillarID()
        var edgeIDsByPillarID: [String: Set<String>] = [:]

        for edge in resolvedEdges {
            for pillarID in edge.data.pillarIds ?? [] where !pillarID.isEmpty {
                edgeIDsByPillarID[pillarID, default: []].insert(edge.id)
            }
        }

        for assignment in pillarAssignments {
            let pillarID = assignment.pillarId.trimmingCharacters(in: .whitespacesAndNewlines)
            if pillarID.isEmpty {
                continue
            }
            for edgeID in assignment.graphEdgeIds where edgeByID[edgeID] != nil {
                edgeIDsByPillarID[pillarID, default: []].insert(edgeID)
            }
        }

        for edge in resolvedEdges {
            for (pillarID, ownedNodeIDs) in nodeIDsByPillarID where ownedNodeIDs.contains(edge.data.source) && ownedNodeIDs.contains(edge.data.target) {
                edgeIDsByPillarID[pillarID, default: []].insert(edge.id)
            }
        }

        return edgeIDsByPillarID
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
        let previousHabitPlannerState = habitPlannerState
        snapshot = mutation.snapshot
        dailyCheckIns = mutation.dailyCheckIns
        dailyDoseProgress = mutation.dailyDoseProgress
        interventionCompletionEvents = mutation.interventionCompletionEvents
        interventionDoseSettings = mutation.interventionDoseSettings
        activeInterventions = mutation.activeInterventions
        let plannerStateDidChange: Bool
        if let nextPlannerState = nextPlannerStateForCompletionTransition(
            interventionID: inputID,
            previousSnapshot: previousSnapshot,
            nextSnapshot: mutation.snapshot
        ) {
            habitPlannerState = nextPlannerState
            plannerStateDidChange = true
        } else {
            plannerStateDidChange = false
        }
        refreshPlanningState()
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextInputCheckOperationToken()
        Task {
            do {
                let patchToPersist = patchIncludingHabitPlannerState(
                    mutation.patch,
                    includePlannerState: plannerStateDidChange
                )
                try await persistPatch(patchToPersist)
            } catch {
                guard operationToken == inputCheckOperationToken else { return }
                dailyCheckIns = previousDailyCheckIns
                interventionCompletionEvents = previousInterventionCompletionEvents
                snapshot = previousSnapshot
                habitPlannerState = previousHabitPlannerState
                refreshPlanningState()
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    func recordHigherRungCompletion(
        interventionID: String,
        achievedRungID: String
    ) {
        guard mode == .explore else { return }
        guard snapshot.inputs.contains(where: { $0.id == interventionID && $0.isCheckedToday }) else {
            return
        }
        guard let ladder = ladderByInterventionID[interventionID], !ladder.rungs.isEmpty else {
            return
        }
        guard let achievedIndex = ladder.rungs.firstIndex(where: { $0.id == achievedRungID }) else {
            return
        }

        let dayKey = Self.localDateKey(from: nowProvider())
        let previousDayKey = Self.shiftedDayKey(dayKey, by: -1)
        let previousState = habitPlannerState
        var nextEntries = habitPlannerState.entriesByInterventionID
        let existing = nextEntries[interventionID] ?? .empty

        let completionIndex = min(existing.currentRungIndex, achievedIndex)
        let completedYesterday = previousDayKey != nil && existing.lastCompletedDayKey == previousDayKey
        let nextStreak = completedYesterday ? existing.consecutiveCompletions + 1 : 1
        let promotedIndex = nextStreak >= 3 ? max(0, completionIndex - 1) : completionIndex
        let nextConsecutiveCompletions = nextStreak >= 3 ? 0 : nextStreak

        nextEntries[interventionID] = HabitPlannerEntryState(
            currentRungIndex: promotedIndex,
            consecutiveCompletions: nextConsecutiveCompletions,
            lastCompletedDayKey: dayKey,
            lastSuggestedDayKey: dayKey,
            learnedDurationMinutes: existing.learnedDurationMinutes
        )
        habitPlannerState = HabitPlannerState(
            entriesByInterventionID: nextEntries,
            updatedAt: Self.timestamp(from: nowProvider())
        )
        refreshPlanningState()

        Task {
            do {
                try await persistPatch(.habitPlannerState(habitPlannerState))
            } catch {
                habitPlannerState = previousState
                refreshPlanningState()
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
            configuredFields: morningCheckInFields,
            at: nowProvider()
        ) else { return }

        let previousSelection = morningOutcomeSelection
        let previousMorningStates = morningStates
        morningOutcomeSelection = mutation.morningOutcomeSelection
        morningStates = mutation.morningStates
        refreshPlanningState()
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
                refreshPlanningState()
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    func setFoundationCheckInValue(_ value: Int?, for questionID: String) {
        guard mode == .explore else { return }
        guard foundationRequiredQuestionIDs.contains(questionID) else { return }
        if let value, !(0...10).contains(value) {
            return
        }

        let nightID = morningOutcomeSelection.nightID
        let previousCheckIns = foundationCheckIns
        let previousPillarCheckIns = pillarCheckIns
        let previousResponses = foundationCheckInResponsesByQuestionID

        var nextResponses = foundationCheckInResponsesByQuestionID
        if let value {
            nextResponses[questionID] = value
        } else {
            nextResponses.removeValue(forKey: questionID)
        }
        foundationCheckInResponsesByQuestionID = nextResponses

        let graphVersion = progressQuestionSetState?.activeSourceGraphVersion
            ?? graphProjectionHub.guide.graphVersion
            ?? "graph-unknown"
        let sourceQuestions = foundationCheckInQuestions
        let associatedNodeIDs = sourceQuestions.flatMap(\.sourceNodeIDs)
        let associatedEdgeIDs = sourceQuestions.flatMap(\.sourceEdgeIDs)
        let association = GraphAssociationRef(
            graphVersion: graphVersion,
            nodeIDs: associatedNodeIDs,
            edgeIDs: associatedEdgeIDs
        )
        let createdAt = Self.timestamp(from: nowProvider())
        let nextCheckIn = FoundationCheckIn(
            nightId: nightID,
            responsesByQuestionId: nextResponses,
            createdAt: createdAt,
            graphAssociation: association
        )
        var responsesByPillarID: [String: Int] = [:]
        for (responseQuestionID, responseValue) in nextResponses {
            guard let pillarID = pillarID(fromQuestionID: responseQuestionID) else {
                continue
            }
            responsesByPillarID[pillarID] = responseValue
        }
        let nextPillarCheckIn = PillarCheckIn(
            nightId: nightID,
            responsesByPillarId: responsesByPillarID,
            createdAt: createdAt,
            graphAssociation: association
        )
        foundationCheckIns = Self.upsertFoundationCheckIn(nextCheckIn, in: foundationCheckIns)
        pillarCheckIns = Self.upsertPillarCheckIn(nextPillarCheckIn, in: pillarCheckIns)
        refreshPlanningState()

        let operationToken = nextFoundationCheckInOperationToken()
        Task {
            do {
                let patch = UserDataPatch(
                    experienceFlow: nil,
                    dailyCheckIns: nil,
                    dailyDoseProgress: nil,
                    interventionCompletionEvents: nil,
                    interventionDoseSettings: nil,
                    appleHealthConnections: nil,
                    morningStates: nil,
                    foundationCheckIns: foundationCheckIns,
                    pillarCheckIns: pillarCheckIns,
                    activeInterventions: nil,
                    hiddenInterventions: nil
                )
                try await persistPatch(patch)
            } catch {
                guard operationToken == foundationCheckInOperationToken else { return }
                foundationCheckIns = previousCheckIns
                pillarCheckIns = previousPillarCheckIns
                foundationCheckInResponsesByQuestionID = previousResponses
                refreshPlanningState()
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

    private func nextFoundationCheckInOperationToken() -> Int {
        foundationCheckInOperationToken += 1
        return foundationCheckInOperationToken
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
        let previousHabitPlannerState = habitPlannerState
        snapshot = mutation.snapshot
        dailyCheckIns = mutation.dailyCheckIns
        dailyDoseProgress = mutation.dailyDoseProgress
        interventionCompletionEvents = mutation.interventionCompletionEvents
        interventionDoseSettings = mutation.interventionDoseSettings
        activeInterventions = mutation.activeInterventions
        let plannerStateDidChange: Bool
        if let nextPlannerState = nextPlannerStateForCompletionTransition(
            interventionID: inputID,
            previousSnapshot: previousSnapshot,
            nextSnapshot: mutation.snapshot
        ) {
            habitPlannerState = nextPlannerState
            plannerStateDidChange = true
        } else {
            plannerStateDidChange = false
        }
        refreshPlanningState()
        exploreFeedback = mutation.successMessage
        announce(mutation.successMessage)

        let operationToken = nextInputDoseOperationToken()
        Task {
            do {
                let patchToPersist = patchIncludingHabitPlannerState(
                    mutation.patch,
                    includePlannerState: plannerStateDidChange
                )
                try await persistPatch(patchToPersist)
            } catch {
                guard operationToken == inputDoseOperationToken else { return }
                dailyDoseProgress = previousDailyDoseProgress
                interventionCompletionEvents = previousInterventionCompletionEvents
                snapshot = previousSnapshot
                habitPlannerState = previousHabitPlannerState
                refreshPlanningState()
                exploreFeedback = mutation.failureMessage
                announce(mutation.failureMessage)
            }
        }
    }

    private func nextPlannerStateForCompletionTransition(
        interventionID: String,
        previousSnapshot: DashboardSnapshot,
        nextSnapshot: DashboardSnapshot
    ) -> HabitPlannerState? {
        guard let previousInput = previousSnapshot.inputs.first(where: { $0.id == interventionID }) else {
            return nil
        }
        guard let nextInput = nextSnapshot.inputs.first(where: { $0.id == interventionID }) else {
            return nil
        }
        guard previousInput.isCheckedToday == false, nextInput.isCheckedToday else {
            return nil
        }

        return dailyPlanner.recordCompletion(
            interventionID: interventionID,
            plannerState: habitPlannerState,
            dayKey: Self.localDateKey(from: nowProvider())
        )
    }

    private func patchIncludingHabitPlannerState(
        _ patch: UserDataPatch,
        includePlannerState: Bool
    ) -> UserDataPatch {
        guard includePlannerState else {
            return patch
        }

        return UserDataPatch(
            experienceFlow: patch.experienceFlow,
            dailyCheckIns: patch.dailyCheckIns,
            dailyDoseProgress: patch.dailyDoseProgress,
            interventionCompletionEvents: patch.interventionCompletionEvents,
            interventionDoseSettings: patch.interventionDoseSettings,
            appleHealthConnections: patch.appleHealthConnections,
            nightOutcomes: patch.nightOutcomes,
            morningStates: patch.morningStates,
            foundationCheckIns: patch.foundationCheckIns,
            userDefinedPillars: patch.userDefinedPillars,
            pillarAssignments: patch.pillarAssignments,
            pillarCheckIns: patch.pillarCheckIns,
            activeInterventions: patch.activeInterventions,
            hiddenInterventions: patch.hiddenInterventions,
            customCausalDiagram: patch.customCausalDiagram,
            wakeDaySleepAttributionMigrated: patch.wakeDaySleepAttributionMigrated,
            progressQuestionSetState: patch.progressQuestionSetState,
            gardenAliasOverrides: patch.gardenAliasOverrides,
            plannerPreferencesState: patch.plannerPreferencesState,
            habitPlannerState: habitPlannerState,
            healthLensState: patch.healthLensState,
            globalLensSelection: patch.globalLensSelection
        )
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

    private static func shiftedDayKey(_ dayKey: String, by offset: Int) -> String? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        guard
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = Calendar(identifier: .gregorian)
        guard let date = components.date else {
            return nil
        }
        guard let shiftedDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date) else {
            return nil
        }
        let shiftedComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: shiftedDate)
        guard
            let shiftedYear = shiftedComponents.year,
            let shiftedMonth = shiftedComponents.month,
            let shiftedDay = shiftedComponents.day
        else {
            return nil
        }

        return String(format: "%04d-%02d-%02d", shiftedYear, shiftedMonth, shiftedDay)
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

    private static func morningOutcomeField(fromProgressQuestionID questionID: String) -> MorningOutcomeField? {
        switch questionID {
        case "morning.globalSensation":
            return .globalSensation
        case "morning.neckTightness":
            return .neckTightness
        case "morning.jawSoreness":
            return .jawSoreness
        case "morning.earFullness":
            return .earFullness
        case "morning.healthAnxiety":
            return .healthAnxiety
        case "morning.stressLevel":
            return .stressLevel
        case "morning.morningHeadache":
            return .morningHeadache
        case "morning.dryMouth":
            return .dryMouth
        default:
            return nil
        }
    }

    private var activePillarsForProgress: [HealthPillarDefinition] {
        projectedHealthLensPillars
    }

    private func pillarQuestionID(for pillar: HealthPillar) -> String {
        "pillar.\(pillar.id)"
    }

    private func pillarID(fromQuestionID questionID: String) -> String? {
        guard questionID.hasPrefix("pillar.") else {
            return nil
        }
        let pillarID = String(questionID.dropFirst("pillar.".count))
        return pillarID.isEmpty ? nil : pillarID
    }

    private func defaultPillarQuestion(for pillar: HealthPillarDefinition) -> GraphDerivedProgressQuestion {
        let sourceNodeIDs = (ownedGraphNodeIDsByPillarID()[pillar.id.id] ?? []).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let sourceEdgeIDs = (ownedGraphEdgeIDsByPillarID()[pillar.id.id] ?? []).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return GraphDerivedProgressQuestion(
            id: pillarQuestionID(for: pillar.id),
            title: "How was your \(pillar.title.lowercased()) today?",
            sourceNodeIDs: sourceNodeIDs,
            sourceEdgeIDs: sourceEdgeIDs
        )
    }

    private static func progressQuestionID(from outcomeField: MorningOutcomeField) -> String {
        "morning.\(outcomeField.rawValue)"
    }

    private static func deduplicatedProgressQuestions(
        _ questions: [GraphDerivedProgressQuestion]
    ) -> [GraphDerivedProgressQuestion] {
        var dedupedQuestions: [GraphDerivedProgressQuestion] = []
        var seenQuestionIDs = Set<String>()

        for question in questions where seenQuestionIDs.insert(question.id).inserted {
            dedupedQuestions.append(question)
        }

        return dedupedQuestions
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

    private static func foundationResponses(
        for nightID: String,
        foundationCheckIns: [FoundationCheckIn],
        pillarCheckIns: [PillarCheckIn]
    ) -> [String: Int] {
        if let pillarCheckIn = pillarCheckIns.first(where: { $0.nightId == nightID }) {
            var responsesByQuestionID: [String: Int] = [:]
            for (pillarID, value) in pillarCheckIn.responsesByPillarId {
                responsesByQuestionID["pillar.\(pillarID)"] = value
            }
            return responsesByQuestionID
        }

        return foundationCheckIns.first(where: { $0.nightId == nightID })?.responsesByQuestionId ?? [:]
    }

    private static func upsertFoundationCheckIn(
        _ checkIn: FoundationCheckIn,
        in existingCheckIns: [FoundationCheckIn]
    ) -> [FoundationCheckIn] {
        var mutableCheckIns = existingCheckIns
        guard let existingIndex = mutableCheckIns.firstIndex(where: { $0.nightId == checkIn.nightId }) else {
            mutableCheckIns.append(checkIn)
            return mutableCheckIns.sorted { $0.nightId > $1.nightId }
        }

        mutableCheckIns[existingIndex] = checkIn
        return mutableCheckIns.sorted { $0.nightId > $1.nightId }
    }

    private static func upsertPillarCheckIn(
        _ checkIn: PillarCheckIn,
        in existingCheckIns: [PillarCheckIn]
    ) -> [PillarCheckIn] {
        var mutableCheckIns = existingCheckIns
        guard let existingIndex = mutableCheckIns.firstIndex(where: { $0.nightId == checkIn.nightId }) else {
            mutableCheckIns.append(checkIn)
            return mutableCheckIns.sorted { $0.nightId > $1.nightId }
        }

        mutableCheckIns[existingIndex] = checkIn
        return mutableCheckIns.sorted { $0.nightId > $1.nightId }
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

    private static func slug(from value: String) -> String {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if normalized.isEmpty {
            return "pillar"
        }
        return normalized
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
