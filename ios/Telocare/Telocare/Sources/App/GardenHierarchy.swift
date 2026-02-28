import Foundation

struct GardenHierarchySelection: Equatable {
    var selectedNodePath: [String]

    static let all = GardenHierarchySelection(selectedNodePath: [])
}

enum GardenThemeKey: String, Equatable, CaseIterable, Sendable {
    case meadow
    case sunrise
    case tide
    case ember
    case alpine
    case orchard
}

struct GardenClusterSignature: Hashable, Equatable, Sendable {
    let rawValue: String

    init(nodeIDs: [String]) {
        rawValue = nodeIDs.sorted().joined(separator: "|")
    }
}

struct WeightedGardenCluster: Equatable, Sendable {
    let signature: GardenClusterSignature
    let nodeIDs: [String]
    let inputIDs: [String]
    let weightedCoverage: Double
    let affinityByInputID: [String: Double]
}

struct GardenClusterSnapshot: Equatable, Identifiable, Sendable {
    let nodeID: String
    let nodeIDs: [String]
    let title: String
    let inputIDs: [String]
    let activeCount: Int
    let checkedTodayCount: Int
    let bloomLevel: Double
    let themeKey: GardenThemeKey

    var id: String {
        nodeID
    }

    var summaryText: String {
        "\(checkedTodayCount)/\(activeCount) done"
    }
}

typealias SubGardenSnapshot = GardenClusterSnapshot

struct GardenHierarchyLevel: Equatable, Sendable {
    let depth: Int
    let clusters: [GardenClusterSnapshot]
}

struct GardenHierarchyBuildResult: Equatable, Sendable {
    let filteredInputs: [InputStatus]
    let levels: [GardenHierarchyLevel]
    let resolvedNodePath: [String]
    let resolvedClusterPath: [GardenClusterSnapshot]
}
