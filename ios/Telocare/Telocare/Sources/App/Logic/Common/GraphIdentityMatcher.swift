import Foundation

enum GraphIdentityMatcher {
    static func edgeIdentityMatches(
        edgeData: GraphEdgeData,
        sourceID: String,
        targetID: String,
        label: String?,
        edgeType: String?
    ) -> Bool {
        guard edgeData.source == sourceID else { return false }
        guard edgeData.target == targetID else { return false }
        guard normalizedOptionalString(edgeData.label) == normalizedOptionalString(label) else { return false }
        return normalizedOptionalString(edgeData.edgeType) == normalizedOptionalString(edgeType)
    }

    static func firstLine(_ value: String) -> String {
        value.components(separatedBy: "\n").first ?? value
    }

    static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
