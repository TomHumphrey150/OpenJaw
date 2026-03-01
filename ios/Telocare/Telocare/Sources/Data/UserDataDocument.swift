import Foundation

struct UserDataDocument: Codable, Equatable {
    let version: Int
    let lastExport: String?
    let personalStudies: [PersonalStudy]
    let notes: [PersonalNote]
    let experiments: [PersonalExperiment]
    let interventionRatings: [InterventionRating]
    let dailyCheckIns: [String: [String]]
    let dailyDoseProgress: [String: [String: Double]]
    let interventionCompletionEvents: [InterventionCompletionEvent]
    let interventionDoseSettings: [String: DoseSettings]
    let appleHealthConnections: [String: AppleHealthConnection]
    let nightExposures: [NightExposure]
    let nightOutcomes: [NightOutcome]
    let morningStates: [MorningState]
    let morningQuestionnaire: MorningQuestionnaire?
    let foundationCheckIns: [FoundationCheckIn]
    let userDefinedPillars: [UserDefinedPillar]
    let pillarAssignments: [PillarAssignment]
    let pillarCheckIns: [PillarCheckIn]
    let progressQuestionSetState: ProgressQuestionSetState?
    let plannerPreferencesState: PlannerPreferencesState?
    let habitPlannerState: HabitPlannerState?
    let healthLensState: HealthLensState?
    let wakeDaySleepAttributionMigrated: Bool
    let habitTrials: [HabitTrialWindow]
    let habitClassifications: [HabitClassification]
    let activeInterventions: [String]
    let hiddenInterventions: [String]
    let unlockedAchievements: [String]
    let customCausalDiagram: CustomCausalDiagram?
    let gardenAliasOverrides: [GardenAliasOverride]
    let experienceFlow: ExperienceFlow

    static let empty = UserDataDocument(
        version: 1,
        lastExport: nil,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings: [],
        dailyCheckIns: [:],
        dailyDoseProgress: [:],
        interventionCompletionEvents: [],
        interventionDoseSettings: [:],
        appleHealthConnections: [:],
        nightExposures: [],
        nightOutcomes: [],
        morningStates: [],
        morningQuestionnaire: nil,
        foundationCheckIns: [],
        userDefinedPillars: [],
        pillarAssignments: [],
        pillarCheckIns: [],
        progressQuestionSetState: nil,
        plannerPreferencesState: nil,
        habitPlannerState: nil,
        healthLensState: nil,
        wakeDaySleepAttributionMigrated: false,
        habitTrials: [],
        habitClassifications: [],
        activeInterventions: [],
        hiddenInterventions: [],
        unlockedAchievements: [],
        customCausalDiagram: nil,
        gardenAliasOverrides: [],
        experienceFlow: .empty
    )

    init(
        version: Int,
        lastExport: String?,
        personalStudies: [PersonalStudy],
        notes: [PersonalNote],
        experiments: [PersonalExperiment],
        interventionRatings: [InterventionRating],
        dailyCheckIns: [String: [String]],
        dailyDoseProgress: [String: [String: Double]] = [:],
        interventionCompletionEvents: [InterventionCompletionEvent] = [],
        interventionDoseSettings: [String: DoseSettings] = [:],
        appleHealthConnections: [String: AppleHealthConnection] = [:],
        nightExposures: [NightExposure],
        nightOutcomes: [NightOutcome],
        morningStates: [MorningState],
        morningQuestionnaire: MorningQuestionnaire? = nil,
        foundationCheckIns: [FoundationCheckIn] = [],
        userDefinedPillars: [UserDefinedPillar] = [],
        pillarAssignments: [PillarAssignment] = [],
        pillarCheckIns: [PillarCheckIn] = [],
        progressQuestionSetState: ProgressQuestionSetState? = nil,
        plannerPreferencesState: PlannerPreferencesState? = nil,
        habitPlannerState: HabitPlannerState? = nil,
        healthLensState: HealthLensState? = nil,
        wakeDaySleepAttributionMigrated: Bool = false,
        habitTrials: [HabitTrialWindow],
        habitClassifications: [HabitClassification],
        activeInterventions: [String] = [],
        hiddenInterventions: [String],
        unlockedAchievements: [String],
        customCausalDiagram: CustomCausalDiagram?,
        gardenAliasOverrides: [GardenAliasOverride] = [],
        experienceFlow: ExperienceFlow
    ) {
        self.version = version
        self.lastExport = lastExport
        self.personalStudies = personalStudies
        self.notes = notes
        self.experiments = experiments
        self.interventionRatings = interventionRatings
        self.dailyCheckIns = dailyCheckIns
        self.dailyDoseProgress = dailyDoseProgress
        self.interventionCompletionEvents = interventionCompletionEvents
        self.interventionDoseSettings = interventionDoseSettings
        self.appleHealthConnections = appleHealthConnections
        self.nightExposures = nightExposures
        self.nightOutcomes = nightOutcomes
        self.morningStates = morningStates
        self.morningQuestionnaire = morningQuestionnaire
        self.foundationCheckIns = foundationCheckIns
        self.userDefinedPillars = userDefinedPillars
        self.pillarAssignments = pillarAssignments
        self.pillarCheckIns = pillarCheckIns
        self.progressQuestionSetState = progressQuestionSetState
        self.plannerPreferencesState = plannerPreferencesState
        self.habitPlannerState = habitPlannerState
        self.healthLensState = healthLensState
        self.wakeDaySleepAttributionMigrated = wakeDaySleepAttributionMigrated
        self.habitTrials = habitTrials
        self.habitClassifications = habitClassifications
        self.activeInterventions = activeInterventions
        self.hiddenInterventions = hiddenInterventions
        self.unlockedAchievements = unlockedAchievements
        self.customCausalDiagram = customCausalDiagram
        self.gardenAliasOverrides = gardenAliasOverrides
        self.experienceFlow = experienceFlow
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case lastExport
        case personalStudies
        case notes
        case experiments
        case interventionRatings
        case dailyCheckIns
        case dailyDoseProgress
        case interventionCompletionEvents
        case interventionDoseSettings
        case appleHealthConnections
        case nightExposures
        case nightOutcomes
        case morningStates
        case morningQuestionnaire
        case foundationCheckIns
        case userDefinedPillars
        case pillarAssignments
        case pillarCheckIns
        case progressQuestionSetState
        case plannerPreferencesState
        case habitPlannerState
        case healthLensState
        case wakeDaySleepAttributionMigrated
        case habitTrials
        case habitClassifications
        case activeInterventions
        case hiddenInterventions
        case unlockedAchievements
        case customCausalDiagram
        case gardenAliasOverrides
        case experienceFlow
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case globalLensSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        lastExport = try container.decodeIfPresent(String.self, forKey: .lastExport)
        personalStudies = try container.decodeIfPresent([PersonalStudy].self, forKey: .personalStudies) ?? []
        notes = try container.decodeIfPresent([PersonalNote].self, forKey: .notes) ?? []
        experiments = try container.decodeIfPresent([PersonalExperiment].self, forKey: .experiments) ?? []
        interventionRatings = try container.decodeIfPresent([InterventionRating].self, forKey: .interventionRatings) ?? []
        dailyCheckIns = try container.decodeIfPresent([String: [String]].self, forKey: .dailyCheckIns) ?? [:]
        dailyDoseProgress = try container.decodeIfPresent([String: [String: Double]].self, forKey: .dailyDoseProgress) ?? [:]
        interventionCompletionEvents = try container.decodeIfPresent([InterventionCompletionEvent].self, forKey: .interventionCompletionEvents) ?? []
        interventionDoseSettings = try container.decodeIfPresent([String: DoseSettings].self, forKey: .interventionDoseSettings) ?? [:]
        appleHealthConnections = try container.decodeIfPresent([String: AppleHealthConnection].self, forKey: .appleHealthConnections) ?? [:]
        nightExposures = try container.decodeIfPresent([NightExposure].self, forKey: .nightExposures) ?? []
        nightOutcomes = try container.decodeIfPresent([NightOutcome].self, forKey: .nightOutcomes) ?? []
        morningStates = try container.decodeIfPresent([MorningState].self, forKey: .morningStates) ?? []
        morningQuestionnaire = try container.decodeIfPresent(MorningQuestionnaire.self, forKey: .morningQuestionnaire)
        foundationCheckIns = try container.decodeIfPresent([FoundationCheckIn].self, forKey: .foundationCheckIns) ?? []
        userDefinedPillars = try container.decodeIfPresent([UserDefinedPillar].self, forKey: .userDefinedPillars) ?? []
        pillarAssignments = try container.decodeIfPresent([PillarAssignment].self, forKey: .pillarAssignments) ?? []
        pillarCheckIns = try container.decodeIfPresent([PillarCheckIn].self, forKey: .pillarCheckIns) ?? []
        progressQuestionSetState = try container.decodeIfPresent(ProgressQuestionSetState.self, forKey: .progressQuestionSetState)
        plannerPreferencesState = try container.decodeIfPresent(PlannerPreferencesState.self, forKey: .plannerPreferencesState)
        habitPlannerState = try container.decodeIfPresent(HabitPlannerState.self, forKey: .habitPlannerState)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        healthLensState = try container.decodeIfPresent(HealthLensState.self, forKey: .healthLensState)
            ?? legacyContainer.decodeIfPresent(HealthLensState.self, forKey: .globalLensSelection)
        wakeDaySleepAttributionMigrated = try container.decodeIfPresent(Bool.self, forKey: .wakeDaySleepAttributionMigrated) ?? false
        habitTrials = try container.decodeIfPresent([HabitTrialWindow].self, forKey: .habitTrials) ?? []
        habitClassifications = try container.decodeIfPresent([HabitClassification].self, forKey: .habitClassifications) ?? []
        activeInterventions = try container.decodeIfPresent([String].self, forKey: .activeInterventions) ?? []
        hiddenInterventions = try container.decodeIfPresent([String].self, forKey: .hiddenInterventions) ?? []
        unlockedAchievements = try container.decodeIfPresent([String].self, forKey: .unlockedAchievements) ?? []
        customCausalDiagram = try container.decodeIfPresent(CustomCausalDiagram.self, forKey: .customCausalDiagram)
        gardenAliasOverrides = try container.decodeIfPresent([GardenAliasOverride].self, forKey: .gardenAliasOverrides) ?? []
        experienceFlow = try container.decodeIfPresent(ExperienceFlow.self, forKey: .experienceFlow) ?? .empty
    }
}

struct PersonalNote: Codable, Equatable, Identifiable {
    let id: String
    let targetType: NoteTargetType
    let targetId: String
    let content: String
    let createdAt: String
    let updatedAt: String
}

enum NoteTargetType: String, Codable, Equatable {
    case citation
    case intervention
    case causalNode = "causal_node"
    case general
}

struct PersonalStudy: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let source: String
    let year: Int
    let url: String
    let type: CitationType

    let studyDesign: StudyDesign?
    let sampleSize: Int?
    let sampleSizeNote: String?
    let effectSize: EffectSize?
    let pValue: Double?
    let confidenceInterval: String?
    let causalityType: CausalityType?
    let replicationStatus: ReplicationStatus?
    let population: Population?
    let comparisonGroup: String?
    let primaryOutcome: String?
    let secondaryOutcomes: [String]?
    let fundingSource: String?
    let conflictOfInterest: String?
    let keyFindings: String?
    let limitations: String?

    let isPersonal: Bool
    let addedAt: String
    let personalNotes: String?
}

enum CitationType: String, Codable, Equatable {
    case cochrane
    case systematicReview
    case metaAnalysis
    case rct
    case review
    case guideline
    case observational
}

enum StudyDesign: String, Codable, Equatable {
    case rct
    case systematicReview = "systematic_review"
    case metaAnalysis = "meta_analysis"
    case cohort
    case caseControl = "case_control"
    case crossSectional = "cross_sectional"
    case caseSeries = "case_series"
    case caseReport = "case_report"
    case mechanistic
    case guideline
}

enum EffectSizeType: String, Codable, Equatable {
    case cohensD = "cohens_d"
    case oddsRatio = "odds_ratio"
    case riskRatio = "risk_ratio"
    case hazardRatio = "hazard_ratio"
    case smd
    case percentage
    case other
}

struct EffectSize: Codable, Equatable {
    let type: EffectSizeType
    let value: Double?
    let ci95Lower: Double?
    let ci95Upper: Double?
    let description: String?
}

struct Population: Codable, Equatable {
    let ageRange: String?
    let demographics: String?
    let inclusionCriteria: String?
    let exclusionCriteria: String?
}

enum CausalityType: String, Codable, Equatable {
    case causal
    case correlational
    case mechanistic
}

enum ReplicationStatus: String, Codable, Equatable {
    case replicated
    case singleStudy = "single_study"
    case conflicting
}

struct PersonalExperiment: Codable, Equatable, Identifiable {
    let id: String
    let interventionId: String
    let interventionName: String
    let startDate: String
    let endDate: String?
    let status: ExperimentStatus
    let observations: [ExperimentObservation]
    let effectiveness: PersonalEffectiveness?
    let summary: String?
}

struct ExperimentObservation: Codable, Equatable, Identifiable {
    let id: String
    let date: String
    let note: String
    let rating: Int?
    let metrics: [String: MetricValue]?
}

enum MetricValue: Codable, Equatable {
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }

        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported metric value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value):
            try container.encode(value)
        case .text(let value):
            try container.encode(value)
        }
    }
}

enum ExperimentStatus: String, Codable, Equatable {
    case active
    case completed
    case abandoned
}

enum PersonalEffectiveness: String, Codable, Equatable {
    case worksForMe = "works_for_me"
    case doesNotWork = "doesnt_work"
    case untested
    case inconclusive
    case ineffective
    case modest
    case effective
    case highlyEffective = "highly_effective"
}

struct InterventionRating: Codable, Equatable {
    let interventionId: String
    let effectiveness: String
    let notes: String?
    let lastUpdated: String
}

enum InterventionCompletionEventSource: String, Codable, Equatable, Hashable, Sendable {
    case binaryCheck
    case doseIncrement
}

struct InterventionCompletionEvent: Codable, Equatable, Hashable, Sendable {
    let interventionId: String
    let occurredAt: String
    let source: InterventionCompletionEventSource
    let graphAssociation: GraphAssociationRef?

    init(
        interventionId: String,
        occurredAt: String,
        source: InterventionCompletionEventSource,
        graphAssociation: GraphAssociationRef? = nil
    ) {
        self.interventionId = interventionId
        self.occurredAt = occurredAt
        self.source = source
        self.graphAssociation = graphAssociation
    }
}

struct DoseSettings: Codable, Equatable, Sendable {
    let dailyGoal: Double
    let increment: Double
}

enum AppleHealthSyncStatus: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case syncing
    case synced
    case noData
    case failed
}

struct AppleHealthConnection: Codable, Equatable, Sendable {
    let isConnected: Bool
    let connectedAt: String?
    let lastSyncAt: String?
    let lastSyncStatus: AppleHealthSyncStatus
    let lastErrorCode: String?

    init(
        isConnected: Bool,
        connectedAt: String?,
        lastSyncAt: String?,
        lastSyncStatus: AppleHealthSyncStatus,
        lastErrorCode: String?
    ) {
        self.isConnected = isConnected
        self.connectedAt = connectedAt
        self.lastSyncAt = lastSyncAt
        self.lastSyncStatus = lastSyncStatus
        self.lastErrorCode = lastErrorCode
    }

    private enum CodingKeys: String, CodingKey {
        case isConnected
        case connectedAt
        case lastSyncAt
        case lastSyncStatus
        case lastErrorCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? false
        connectedAt = try container.decodeIfPresent(String.self, forKey: .connectedAt)
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt)
        lastSyncStatus = try container.decodeIfPresent(AppleHealthSyncStatus.self, forKey: .lastSyncStatus) ?? .disconnected
        lastErrorCode = try container.decodeIfPresent(String.self, forKey: .lastErrorCode)
    }
}

struct NightExposure: Codable, Equatable {
    let nightId: String
    let interventionId: String
    let enabled: Bool
    let intensity: Double?
    let tags: [String]?
    let createdAt: String
}

struct NightOutcome: Codable, Equatable, Sendable {
    let nightId: String
    let microArousalCount: Double?
    let microArousalRatePerHour: Double?
    let confidence: Double?
    let totalSleepMinutes: Double?
    let source: String?
    let createdAt: String
    let graphAssociation: GraphAssociationRef?

    init(
        nightId: String,
        microArousalCount: Double?,
        microArousalRatePerHour: Double?,
        confidence: Double?,
        totalSleepMinutes: Double?,
        source: String?,
        createdAt: String,
        graphAssociation: GraphAssociationRef? = nil
    ) {
        self.nightId = nightId
        self.microArousalCount = microArousalCount
        self.microArousalRatePerHour = microArousalRatePerHour
        self.confidence = confidence
        self.totalSleepMinutes = totalSleepMinutes
        self.source = source
        self.createdAt = createdAt
        self.graphAssociation = graphAssociation
    }
}

struct MorningState: Codable, Equatable, Sendable {
    let nightId: String
    let globalSensation: Double?
    let neckTightness: Double?
    let jawSoreness: Double?
    let earFullness: Double?
    let healthAnxiety: Double?
    let stressLevel: Double?
    let morningHeadache: Double?
    let dryMouth: Double?
    let createdAt: String
    let graphAssociation: GraphAssociationRef?

    init(
        nightId: String,
        globalSensation: Double?,
        neckTightness: Double?,
        jawSoreness: Double?,
        earFullness: Double?,
        healthAnxiety: Double?,
        stressLevel: Double? = nil,
        morningHeadache: Double? = nil,
        dryMouth: Double? = nil,
        createdAt: String,
        graphAssociation: GraphAssociationRef? = nil
    ) {
        self.nightId = nightId
        self.globalSensation = globalSensation
        self.neckTightness = neckTightness
        self.jawSoreness = jawSoreness
        self.earFullness = earFullness
        self.healthAnxiety = healthAnxiety
        self.stressLevel = stressLevel
        self.morningHeadache = morningHeadache
        self.dryMouth = dryMouth
        self.createdAt = createdAt
        self.graphAssociation = graphAssociation
    }
}

enum MorningQuestionField: String, Codable, Equatable, Sendable {
    case globalSensation
    case neckTightness
    case jawSoreness
    case earFullness
    case healthAnxiety
    case stressLevel
    case morningHeadache
    case dryMouth
}

struct MorningQuestionnaire: Codable, Equatable, Sendable {
    let enabledFields: [MorningQuestionField]
    let requiredFields: [MorningQuestionField]?
}

struct FoundationCheckIn: Codable, Equatable, Sendable {
    let nightId: String
    let responsesByQuestionId: [String: Int]
    let createdAt: String
    let graphAssociation: GraphAssociationRef?
}

struct UserDefinedPillar: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let templateId: String
    let createdAt: String
    let updatedAt: String
    let isArchived: Bool
}

struct PillarAssignment: Codable, Equatable, Hashable, Sendable {
    let pillarId: String
    let graphNodeIds: [String]
    let graphEdgeIds: [String]
    let interventionIds: [String]
    let questionId: String?
}

struct PillarCheckIn: Codable, Equatable, Sendable {
    let nightId: String
    let responsesByPillarId: [String: Int]
    let createdAt: String
    let graphAssociation: GraphAssociationRef?
}

struct GraphAssociationRef: Codable, Equatable, Hashable, Sendable {
    let graphVersion: String
    let nodeIDs: [String]
    let edgeIDs: [String]

    init(graphVersion: String, nodeIDs: [String], edgeIDs: [String]) {
        self.graphVersion = graphVersion
        self.nodeIDs = nodeIDs.sorted()
        self.edgeIDs = edgeIDs.sorted()
    }
}

struct GraphDerivedProgressQuestion: Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let sourceNodeIDs: [String]
    let sourceEdgeIDs: [String]

    init(id: String, title: String, sourceNodeIDs: [String], sourceEdgeIDs: [String]) {
        self.id = id
        self.title = title
        self.sourceNodeIDs = sourceNodeIDs.sorted()
        self.sourceEdgeIDs = sourceEdgeIDs.sorted()
    }
}

struct ProgressQuestionSetProposal: Codable, Equatable, Sendable {
    let sourceGraphVersion: String
    let proposedQuestionSetVersion: String
    let questions: [GraphDerivedProgressQuestion]
    let createdAt: String
}

struct ProgressQuestionSetState: Codable, Equatable, Sendable {
    let activeQuestionSetVersion: String
    let activeSourceGraphVersion: String
    let activeQuestions: [GraphDerivedProgressQuestion]
    let declinedGraphVersions: [String]
    let pendingProposal: ProgressQuestionSetProposal?
    let updatedAt: String

    init(
        activeQuestionSetVersion: String,
        activeSourceGraphVersion: String,
        activeQuestions: [GraphDerivedProgressQuestion] = [],
        declinedGraphVersions: [String],
        pendingProposal: ProgressQuestionSetProposal?,
        updatedAt: String
    ) {
        self.activeQuestionSetVersion = activeQuestionSetVersion
        self.activeSourceGraphVersion = activeSourceGraphVersion
        self.activeQuestions = activeQuestions
        self.declinedGraphVersions = declinedGraphVersions
        self.pendingProposal = pendingProposal
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case activeQuestionSetVersion
        case activeSourceGraphVersion
        case activeQuestions
        case declinedGraphVersions
        case pendingProposal
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeQuestionSetVersion = try container.decode(String.self, forKey: .activeQuestionSetVersion)
        activeSourceGraphVersion = try container.decode(String.self, forKey: .activeSourceGraphVersion)
        activeQuestions = try container.decodeIfPresent([GraphDerivedProgressQuestion].self, forKey: .activeQuestions) ?? []
        declinedGraphVersions = try container.decodeIfPresent([String].self, forKey: .declinedGraphVersions) ?? []
        pendingProposal = try container.decodeIfPresent(ProgressQuestionSetProposal.self, forKey: .pendingProposal)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeQuestionSetVersion, forKey: .activeQuestionSetVersion)
        try container.encode(activeSourceGraphVersion, forKey: .activeSourceGraphVersion)
        try container.encode(activeQuestions, forKey: .activeQuestions)
        try container.encode(declinedGraphVersions, forKey: .declinedGraphVersions)
        try container.encodeIfPresent(pendingProposal, forKey: .pendingProposal)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct GardenAliasOverride: Codable, Equatable, Hashable, Sendable {
    let signature: String
    let title: String
    let approvedAt: String
    let sourceGraphVersion: String
}

struct GardenNameProposal: Codable, Equatable, Sendable {
    let proposalID: String
    let signature: String
    let currentTitle: String
    let proposedTitle: String
    let explanation: String
    let sourceGraphVersion: String
}

struct HabitTrialWindow: Codable, Equatable, Identifiable {
    let id: String
    let interventionId: String
    let startNightId: String
    let endNightId: String?
    let status: ExperimentStatus
}

struct HabitClassification: Codable, Equatable {
    let interventionId: String
    let status: HabitEffectStatus
    let nightsOn: Int
    let nightsOff: Int
    let microArousalDeltaPct: Double?
    let morningStateDelta: Double?
    let windowQuality: HabitWindowQuality?
    let updatedAt: String
}

enum HabitEffectStatus: String, Codable, Equatable {
    case helpful
    case neutral
    case harmful
    case unknown
}

enum HabitWindowQuality: String, Codable, Equatable {
    case cleanOneVariable = "clean_one_variable"
    case confounded
    case insufficientData = "insufficient_data"
}

struct ExperienceFlow: Codable, Equatable, Sendable {
    let hasCompletedInitialGuidedFlow: Bool
    let lastGuidedEntryDate: String?
    let lastGuidedCompletedDate: String?
    let lastGuidedStatus: ExperienceFlowStatus

    static let empty = ExperienceFlow(
        hasCompletedInitialGuidedFlow: false,
        lastGuidedEntryDate: nil,
        lastGuidedCompletedDate: nil,
        lastGuidedStatus: .notStarted
    )
}

enum ExperienceFlowStatus: String, Codable, Equatable, Sendable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed
    case interrupted
}

struct CustomCausalDiagram: Codable, Equatable, Sendable {
    let graphData: CausalGraphData
    let lastModified: String?
    let graphVersion: String?
    let baseGraphVersion: String?

    init(
        graphData: CausalGraphData,
        lastModified: String?,
        graphVersion: String? = nil,
        baseGraphVersion: String? = nil
    ) {
        self.graphData = graphData
        self.lastModified = lastModified
        self.graphVersion = graphVersion
        self.baseGraphVersion = baseGraphVersion
    }

    private enum CodingKeys: String, CodingKey {
        case graphData
        case nodes
        case edges
        case lastModified
        case graphVersion
        case baseGraphVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let wrappedGraphData = try container.decodeIfPresent(CausalGraphData.self, forKey: .graphData) {
            graphData = wrappedGraphData
            lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
            graphVersion = try container.decodeIfPresent(String.self, forKey: .graphVersion)
            baseGraphVersion = try container.decodeIfPresent(String.self, forKey: .baseGraphVersion)
            return
        }

        let directNodes = try container.decodeIfPresent([GraphNodeElement].self, forKey: .nodes)
        let directEdges = try container.decodeIfPresent([GraphEdgeElement].self, forKey: .edges)

        guard let directNodes, let directEdges else {
            throw DecodingError.dataCorruptedError(
                forKey: .graphData,
                in: container,
                debugDescription: "customCausalDiagram must contain graphData or direct nodes/edges"
            )
        }

        graphData = CausalGraphData(nodes: directNodes, edges: directEdges)
        lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        graphVersion = try container.decodeIfPresent(String.self, forKey: .graphVersion)
        baseGraphVersion = try container.decodeIfPresent(String.self, forKey: .baseGraphVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(graphData, forKey: .graphData)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encodeIfPresent(graphVersion, forKey: .graphVersion)
        try container.encodeIfPresent(baseGraphVersion, forKey: .baseGraphVersion)
    }
}

struct CausalGraphData: Codable, Equatable, Sendable {
    let nodes: [GraphNodeElement]
    let edges: [GraphEdgeElement]
}

struct GraphNodeElement: Codable, Equatable, Sendable {
    let data: GraphNodeData
}

struct GraphNodeData: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case styleClass
        case confirmed
        case tier
        case tooltip
        case isDeactivated
        case parentId
        case parentIds
        case isExpanded
        case pillarIds
    }

    let id: String
    let label: String
    let styleClass: String
    let confirmed: String?
    let tier: Int?
    let tooltip: GraphTooltip?
    let isDeactivated: Bool?
    let parentIds: [String]?
    let parentId: String?
    let isExpanded: Bool?
    let pillarIds: [String]?

    init(
        id: String,
        label: String,
        styleClass: String,
        confirmed: String?,
        tier: Int?,
        tooltip: GraphTooltip?,
        isDeactivated: Bool? = nil,
        parentIds: [String]? = nil,
        parentId: String? = nil,
        isExpanded: Bool? = nil,
        pillarIds: [String]? = nil
    ) {
        let resolvedParentIDs: [String]?
        if let parentIds, !parentIds.isEmpty {
            resolvedParentIDs = parentIds
        } else if let parentId, !parentId.isEmpty {
            resolvedParentIDs = [parentId]
        } else {
            resolvedParentIDs = nil
        }

        self.id = id
        self.label = label
        self.styleClass = styleClass
        self.confirmed = confirmed
        self.tier = tier
        self.tooltip = tooltip
        self.isDeactivated = isDeactivated
        self.parentIds = resolvedParentIDs
        self.parentId = resolvedParentIDs?.first
        self.isExpanded = isExpanded
        self.pillarIds = pillarIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let label = try container.decode(String.self, forKey: .label)
        let styleClass = try container.decode(String.self, forKey: .styleClass)
        let confirmed = try container.decodeIfPresent(String.self, forKey: .confirmed)
        let tier = try container.decodeIfPresent(Int.self, forKey: .tier)
        let tooltip = try container.decodeIfPresent(GraphTooltip.self, forKey: .tooltip)
        let isDeactivated = try container.decodeIfPresent(Bool.self, forKey: .isDeactivated)
        let decodedParentIDs = try container.decodeIfPresent([String].self, forKey: .parentIds)
        let decodedParentID = try container.decodeIfPresent(String.self, forKey: .parentId)
        let isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded)
        let pillarIds = try container.decodeIfPresent([String].self, forKey: .pillarIds)

        self.init(
            id: id,
            label: label,
            styleClass: styleClass,
            confirmed: confirmed,
            tier: tier,
            tooltip: tooltip,
            isDeactivated: isDeactivated,
            parentIds: decodedParentIDs,
            parentId: decodedParentID,
            isExpanded: isExpanded,
            pillarIds: pillarIds
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(styleClass, forKey: .styleClass)
        try container.encodeIfPresent(confirmed, forKey: .confirmed)
        try container.encodeIfPresent(tier, forKey: .tier)
        try container.encodeIfPresent(tooltip, forKey: .tooltip)
        try container.encodeIfPresent(isDeactivated, forKey: .isDeactivated)
        try container.encodeIfPresent(parentIds, forKey: .parentIds)
        try container.encodeIfPresent(parentIds?.first, forKey: .parentId)
        try container.encodeIfPresent(isExpanded, forKey: .isExpanded)
        try container.encodeIfPresent(pillarIds, forKey: .pillarIds)
    }
}

struct GraphTooltip: Codable, Equatable, Sendable {
    let evidence: String?
    let stat: String?
    let citation: String?
    let mechanism: String?
}

struct GraphEdgeElement: Codable, Equatable, Sendable {
    let data: GraphEdgeData
}

struct GraphEdgeData: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case target
        case label
        case edgeType
        case edgeColor
        case tooltip
        case strength
        case isDeactivated
        case pillarIds
    }

    let id: String?
    let source: String
    let target: String
    let label: String?
    let edgeType: String?
    let edgeColor: String?
    let tooltip: String?
    let strength: Double?
    let isDeactivated: Bool?
    let pillarIds: [String]?

    init(
        id: String? = nil,
        source: String,
        target: String,
        label: String?,
        edgeType: String?,
        edgeColor: String?,
        tooltip: String?,
        strength: Double? = nil,
        isDeactivated: Bool? = nil,
        pillarIds: [String]? = nil
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.label = label
        self.edgeType = edgeType
        self.edgeColor = edgeColor
        self.tooltip = tooltip
        self.strength = strength
        self.isDeactivated = isDeactivated
        self.pillarIds = pillarIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        source = try container.decode(String.self, forKey: .source)
        target = try container.decode(String.self, forKey: .target)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        edgeType = try container.decodeIfPresent(String.self, forKey: .edgeType)
        edgeColor = try container.decodeIfPresent(String.self, forKey: .edgeColor)
        tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
        strength = try container.decodeIfPresent(Double.self, forKey: .strength)
        isDeactivated = try container.decodeIfPresent(Bool.self, forKey: .isDeactivated)
        pillarIds = try container.decodeIfPresent([String].self, forKey: .pillarIds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(edgeType, forKey: .edgeType)
        try container.encodeIfPresent(edgeColor, forKey: .edgeColor)
        try container.encodeIfPresent(tooltip, forKey: .tooltip)
        try container.encodeIfPresent(strength, forKey: .strength)
        try container.encodeIfPresent(isDeactivated, forKey: .isDeactivated)
        try container.encodeIfPresent(pillarIds, forKey: .pillarIds)
    }
}
