import Foundation

enum InputTrackingMode: String, Equatable, Hashable, Sendable {
    case binary
    case dose
}

struct InputDoseState: Equatable, Hashable, Sendable {
    let manualValue: Double
    let healthValue: Double?
    let goal: Double
    let increment: Double
    let unit: DoseUnit

    init(
        manualValue: Double,
        healthValue: Double? = nil,
        goal: Double,
        increment: Double,
        unit: DoseUnit
    ) {
        self.manualValue = manualValue
        self.healthValue = healthValue
        self.goal = goal
        self.increment = increment
        self.unit = unit
    }

    init(
        value: Double,
        goal: Double,
        increment: Double,
        unit: DoseUnit
    ) {
        self.init(
            manualValue: value,
            healthValue: nil,
            goal: goal,
            increment: increment,
            unit: unit
        )
    }

    var value: Double {
        max(manualValue, healthValue ?? 0)
    }

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

struct InputAppleHealthState: Equatable, Hashable, Sendable {
    let available: Bool
    let connected: Bool
    let syncStatus: AppleHealthSyncStatus
    let todayHealthValue: Double?
    let lastSyncAt: String?
    let config: AppleHealthConfig?
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
    let completionEvents: [InterventionCompletionEvent]
    let graphNodeID: String?
    let classificationText: String?
    let isActive: Bool
    let evidenceLevel: String?
    let evidenceSummary: String?
    let detailedDescription: String?
    let citationIDs: [String]
    let externalLink: String?
    let appleHealthState: InputAppleHealthState?

    init(
        id: String,
        name: String,
        trackingMode: InputTrackingMode = .binary,
        statusText: String,
        completion: Double,
        isCheckedToday: Bool,
        doseState: InputDoseState? = nil,
        completionEvents: [InterventionCompletionEvent] = [],
        graphNodeID: String? = nil,
        classificationText: String?,
        isActive: Bool,
        evidenceLevel: String?,
        evidenceSummary: String?,
        detailedDescription: String?,
        citationIDs: [String],
        externalLink: String?,
        appleHealthState: InputAppleHealthState? = nil
    ) {
        self.id = id
        self.name = name
        self.trackingMode = trackingMode
        self.statusText = statusText
        self.completion = completion
        self.isCheckedToday = isCheckedToday
        self.doseState = doseState
        self.completionEvents = completionEvents
        self.graphNodeID = graphNodeID
        self.classificationText = classificationText
        self.isActive = isActive
        self.evidenceLevel = evidenceLevel
        self.evidenceSummary = evidenceSummary
        self.detailedDescription = detailedDescription
        self.citationIDs = citationIDs
        self.externalLink = externalLink
        self.appleHealthState = appleHealthState
    }
}
