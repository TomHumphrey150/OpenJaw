import Foundation

enum GardenPathway: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
    case upstream
    case midstream
    case downstream

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upstream:
            return "Roots"
        case .midstream:
            return "Canopy"
        case .downstream:
            return "Bloom"
        }
    }

    var symbolName: String {
        switch self {
        case .upstream:
            return "leaf.fill"
        case .midstream:
            return "tree.fill"
        case .downstream:
            return "camera.macro"
        }
    }

    var subtitle: String {
        switch self {
        case .upstream:
            return "Foundation"
        case .midstream:
            return "Regulation"
        case .downstream:
            return "Relief"
        }
    }

    init?(causalPathway: String?) {
        switch causalPathway?.lowercased() {
        case "upstream":
            self = .upstream
        case "midstream":
            self = .midstream
        case "downstream":
            self = .downstream
        default:
            return nil
        }
    }
}

struct GardenSnapshot: Equatable, Identifiable, Sendable {
    let pathway: GardenPathway
    let activeCount: Int
    let checkedTodayCount: Int
    let weeklyAverage: Double
    let bloomLevel: Double
    let inputIDs: [String]

    var id: String { pathway.rawValue }

    var todayRatio: Double {
        guard activeCount > 0 else { return 0 }
        return Double(checkedTodayCount) / Double(activeCount)
    }

    var summaryText: String {
        "\(checkedTodayCount)/\(activeCount) done"
    }
}
