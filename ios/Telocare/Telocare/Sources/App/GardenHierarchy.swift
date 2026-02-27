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

struct GardenClusterSnapshot: Equatable, Identifiable, Sendable {
    let nodeID: String
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
}
