import Foundation

/// Sorts inputs by evidence robustness.
enum InputScoring {

    /// Sorts inputs by evidence level (most robust first).
    static func sortedByImpact(
        inputs: [InputStatus],
        graphData: CausalGraphData
    ) -> [InputStatus] {
        inputs.sorted { a, b in
            evidenceRank(for: a.evidenceLevel) > evidenceRank(for: b.evidenceLevel)
        }
    }

    /// Returns a numeric rank for evidence level (higher = better).
    private static func evidenceRank(for evidenceLevel: String?) -> Int {
        switch evidenceLevel?.lowercased() {
        case "robust", "strong":
            return 6
        case "moderate-high":
            return 5
        case "moderate":
            return 4
        case "low-moderate":
            return 3
        case "preliminary":
            return 2
        case "mechanism":
            return 1
        case "low":
            return 0
        default:
            return -1
        }
    }
}
