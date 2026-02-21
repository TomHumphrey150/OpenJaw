import Foundation

struct DashboardSnapshot: Equatable {
    let outcomes: OutcomeSummary
    let outcomeRecords: [OutcomeRecord]
    let outcomesMetadata: OutcomesMetadata
    let situation: SituationSummary
    let inputs: [InputStatus]
}

struct OutcomeSummary: Equatable {
    let shieldScore: Int
    let burdenTrendPercent: Int
    let topContributor: String
    let confidence: String
    let burdenProgress: Double
}

struct OutcomeRecord: Equatable, Identifiable {
    let id: String
    let microArousalRatePerHour: Double?
    let microArousalCount: Double?
    let confidence: Double?
    let source: String?
}

struct SituationSummary: Equatable {
    let focusedNode: String
    let tier: String
    let visibleHotspots: Int
    let topSource: String
}

struct InputStatus: Equatable, Identifiable {
    let id: String
    let name: String
    let statusText: String
    let completion: Double
    let isCheckedToday: Bool
    let classificationText: String?
    let isHidden: Bool
    let evidenceLevel: String?
    let evidenceSummary: String?
    let detailedDescription: String?
    let citationIDs: [String]
    let externalLink: String?
}
