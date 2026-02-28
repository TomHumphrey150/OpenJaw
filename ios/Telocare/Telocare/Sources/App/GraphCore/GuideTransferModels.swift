import Foundation

enum GuideTransferSection: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case graph
    case aliases
    case planner

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .graph:
            return "Graph"
        case .aliases:
            return "Aliases"
        case .planner:
            return "Planner"
        }
    }
}

struct GuideGraphTransferPayload: Codable, Equatable, Sendable {
    let graphVersion: String?
    let baseGraphVersion: String?
    let lastModified: String?
    let graphData: CausalGraphData
}

struct GuidePlannerTransferPayload: Codable, Equatable, Sendable {
    let plannerPreferencesState: PlannerPreferencesState
    let habitPlannerState: HabitPlannerState
    let healthLensState: HealthLensState
}

struct GuideExportEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: String
    let sections: [GuideTransferSection]
    let graph: GuideGraphTransferPayload?
    let aliases: [GardenAliasOverride]?
    let planner: GuidePlannerTransferPayload?
}

struct GuideImportPreview: Equatable, Sendable {
    let sections: [GuideTransferSection]
    let summaryLines: [String]
    let validationError: String?

    var isValid: Bool {
        validationError == nil
    }
}
