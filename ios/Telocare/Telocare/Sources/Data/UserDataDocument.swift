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
    let habitTrials: [HabitTrialWindow]
    let habitClassifications: [HabitClassification]
    let activeInterventions: [String]
    let hiddenInterventions: [String]
    let unlockedAchievements: [String]
    let customCausalDiagram: CustomCausalDiagram?
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
        habitTrials: [],
        habitClassifications: [],
        activeInterventions: [],
        hiddenInterventions: [],
        unlockedAchievements: [],
        customCausalDiagram: nil,
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
        habitTrials: [HabitTrialWindow],
        habitClassifications: [HabitClassification],
        activeInterventions: [String] = [],
        hiddenInterventions: [String],
        unlockedAchievements: [String],
        customCausalDiagram: CustomCausalDiagram?,
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
        self.habitTrials = habitTrials
        self.habitClassifications = habitClassifications
        self.activeInterventions = activeInterventions
        self.hiddenInterventions = hiddenInterventions
        self.unlockedAchievements = unlockedAchievements
        self.customCausalDiagram = customCausalDiagram
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
        case habitTrials
        case habitClassifications
        case activeInterventions
        case hiddenInterventions
        case unlockedAchievements
        case customCausalDiagram
        case experienceFlow
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
        habitTrials = try container.decodeIfPresent([HabitTrialWindow].self, forKey: .habitTrials) ?? []
        habitClassifications = try container.decodeIfPresent([HabitClassification].self, forKey: .habitClassifications) ?? []
        activeInterventions = try container.decodeIfPresent([String].self, forKey: .activeInterventions) ?? []
        hiddenInterventions = try container.decodeIfPresent([String].self, forKey: .hiddenInterventions) ?? []
        unlockedAchievements = try container.decodeIfPresent([String].self, forKey: .unlockedAchievements) ?? []
        customCausalDiagram = try container.decodeIfPresent(CustomCausalDiagram.self, forKey: .customCausalDiagram)
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

struct NightOutcome: Codable, Equatable {
    let nightId: String
    let microArousalCount: Double?
    let microArousalRatePerHour: Double?
    let confidence: Double?
    let totalSleepMinutes: Double?
    let source: String?
    let createdAt: String
}

struct MorningState: Codable, Equatable, Sendable {
    let nightId: String
    let globalSensation: Double?
    let neckTightness: Double?
    let jawSoreness: Double?
    let earFullness: Double?
    let healthAnxiety: Double?
    let stressLevel: Double?
    let createdAt: String

    init(
        nightId: String,
        globalSensation: Double?,
        neckTightness: Double?,
        jawSoreness: Double?,
        earFullness: Double?,
        healthAnxiety: Double?,
        stressLevel: Double? = nil,
        createdAt: String
    ) {
        self.nightId = nightId
        self.globalSensation = globalSensation
        self.neckTightness = neckTightness
        self.jawSoreness = jawSoreness
        self.earFullness = earFullness
        self.healthAnxiety = healthAnxiety
        self.stressLevel = stressLevel
        self.createdAt = createdAt
    }
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

    init(graphData: CausalGraphData, lastModified: String?) {
        self.graphData = graphData
        self.lastModified = lastModified
    }

    private enum CodingKeys: String, CodingKey {
        case graphData
        case nodes
        case edges
        case lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let wrappedGraphData = try container.decodeIfPresent(CausalGraphData.self, forKey: .graphData) {
            graphData = wrappedGraphData
            lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(graphData, forKey: .graphData)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
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
    let id: String
    let label: String
    let styleClass: String
    let confirmed: String?
    let tier: Int?
    let tooltip: GraphTooltip?
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
    let source: String
    let target: String
    let label: String?
    let edgeType: String?
    let edgeColor: String?
    let tooltip: String?
}
