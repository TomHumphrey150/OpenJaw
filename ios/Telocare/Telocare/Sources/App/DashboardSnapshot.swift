import Foundation

struct DashboardSnapshot: Equatable {
    let outcomes: OutcomeSummary
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
}
