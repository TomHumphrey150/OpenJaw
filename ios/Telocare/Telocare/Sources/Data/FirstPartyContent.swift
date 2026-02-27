import Foundation

enum InterventionTrackingType: String, Codable, Equatable, Sendable, Hashable {
    case binary
    case timer
    case counter
    case checklist
    case appointment
    case dose
}

enum InterventionTimeOfDay: String, Codable, Equatable, Sendable, Hashable {
    case morning
    case afternoon
    case evening
    case preBed
    case anytime
}

enum DoseUnit: String, Codable, Equatable, Sendable, Hashable {
    case minutes
    case hours
    case milliliters
    case reps
    case breaths

    var displayName: String {
        switch self {
        case .minutes:
            return "min"
        case .hours:
            return "hr"
        case .milliliters:
            return "ml"
        case .reps:
            return "reps"
        case .breaths:
            return "breaths"
        }
    }
}

struct DoseConfig: Codable, Equatable, Sendable, Hashable {
    let unit: DoseUnit
    let defaultDailyGoal: Double
    let defaultIncrement: Double
}

enum AppleHealthIdentifier: String, Codable, Equatable, Sendable, Hashable {
    case appleExerciseTime
    case moderateWorkoutMinutes
    case sleepAnalysis
    case mindfulSession
    case dietaryWater
}

enum AppleHealthAggregation: String, Codable, Equatable, Sendable, Hashable {
    case cumulativeSum
    case durationSum
    case sleepAsleepDurationSum
}

enum AppleHealthDayAttribution: String, Codable, Equatable, Sendable, Hashable {
    case localDay
    case previousNightNoonCutoff
}

struct AppleHealthConfig: Codable, Equatable, Sendable, Hashable {
    let identifier: AppleHealthIdentifier
    let aggregation: AppleHealthAggregation
    let dayAttribution: AppleHealthDayAttribution
}

struct FirstPartyContentBundle: Equatable, Sendable {
    let graphData: CausalGraphData?
    let interventionsCatalog: InterventionsCatalog
    let outcomesMetadata: OutcomesMetadata

    static let empty = FirstPartyContentBundle(
        graphData: nil,
        interventionsCatalog: .empty,
        outcomesMetadata: .empty
    )
}

struct InterventionsCatalog: Codable, Equatable, Sendable {
    let interventions: [InterventionDefinition]

    static let empty = InterventionsCatalog(interventions: [])
}

struct InterventionDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let detailedDescription: String?
    let evidenceLevel: String?
    let evidenceSummary: String?
    let citationIds: [String]?
    let externalLink: String?
    let defaultOrder: Int?
    let legacyIds: [String]?
    let graphNodeId: String?
    let trackingType: InterventionTrackingType?
    let doseConfig: DoseConfig?
    let timeOfDay: [InterventionTimeOfDay]?
    let appleHealthAvailable: Bool?
    let appleHealthConfig: AppleHealthConfig?
    let causalPathway: String?

    init(
        id: String,
        name: String,
        description: String?,
        detailedDescription: String?,
        evidenceLevel: String?,
        evidenceSummary: String?,
        citationIds: [String]?,
        externalLink: String?,
        defaultOrder: Int?,
        legacyIds: [String]? = nil,
        graphNodeId: String? = nil,
        trackingType: InterventionTrackingType? = nil,
        doseConfig: DoseConfig? = nil,
        timeOfDay: [InterventionTimeOfDay]? = nil,
        appleHealthAvailable: Bool? = nil,
        appleHealthConfig: AppleHealthConfig? = nil,
        causalPathway: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.detailedDescription = detailedDescription
        self.evidenceLevel = evidenceLevel
        self.evidenceSummary = evidenceSummary
        self.citationIds = citationIds
        self.externalLink = externalLink
        self.defaultOrder = defaultOrder
        self.legacyIds = legacyIds
        self.graphNodeId = graphNodeId
        self.trackingType = trackingType
        self.doseConfig = doseConfig
        self.timeOfDay = timeOfDay
        self.appleHealthAvailable = appleHealthAvailable
        self.appleHealthConfig = appleHealthConfig
        self.causalPathway = causalPathway
    }

    var citations: [String] {
        citationIds ?? []
    }

    var legacyIDs: [String] {
        legacyIds ?? []
    }
}

struct OutcomesMetadata: Codable, Equatable, Sendable {
    let metrics: [OutcomeMetricDefinition]
    let nodes: [OutcomeNodeMetadata]
    let updatedAt: String?

    static let empty = OutcomesMetadata(metrics: [], nodes: [], updatedAt: nil)
}

struct OutcomeMetricDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let unit: String
    let direction: String
    let description: String
}

struct OutcomeNodeMetadata: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let styleClass: String
    let evidence: String?
    let stat: String?
    let citation: String?
    let mechanism: String?
}
