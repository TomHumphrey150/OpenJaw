import Foundation

enum InputTrackingMode: String, Equatable, Hashable, Sendable {
    case binary
    case dose
}

struct InputDoseState: Equatable, Hashable, Sendable {
    let value: Double
    let goal: Double
    let increment: Double
    let unit: DoseUnit

    var completionClamped: Double {
        guard goal > 0 else {
            return 0
        }

        return max(0, min(1, value / goal))
    }

    var completionRaw: Double {
        guard goal > 0 else {
            return 0
        }

        return max(0, value / goal)
    }

    var isGoalMet: Bool {
        goal > 0 && value >= goal
    }
}

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

struct OutcomeRecord: Equatable, Identifiable, Hashable {
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

struct InputStatus: Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let trackingMode: InputTrackingMode
    let statusText: String
    let completion: Double
    let isCheckedToday: Bool
    let doseState: InputDoseState?
    let graphNodeID: String?
    let classificationText: String?
    let isHidden: Bool
    let evidenceLevel: String?
    let evidenceSummary: String?
    let detailedDescription: String?
    let citationIDs: [String]
    let externalLink: String?

    init(
        id: String,
        name: String,
        trackingMode: InputTrackingMode = .binary,
        statusText: String,
        completion: Double,
        isCheckedToday: Bool,
        doseState: InputDoseState? = nil,
        graphNodeID: String? = nil,
        classificationText: String?,
        isHidden: Bool,
        evidenceLevel: String?,
        evidenceSummary: String?,
        detailedDescription: String?,
        citationIDs: [String],
        externalLink: String?
    ) {
        self.id = id
        self.name = name
        self.trackingMode = trackingMode
        self.statusText = statusText
        self.completion = completion
        self.isCheckedToday = isCheckedToday
        self.doseState = doseState
        self.graphNodeID = graphNodeID
        self.classificationText = classificationText
        self.isHidden = isHidden
        self.evidenceLevel = evidenceLevel
        self.evidenceSummary = evidenceSummary
        self.detailedDescription = detailedDescription
        self.citationIDs = citationIDs
        self.externalLink = externalLink
    }
}
