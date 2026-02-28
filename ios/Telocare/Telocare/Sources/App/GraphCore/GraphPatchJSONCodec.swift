import Foundation

struct GraphPatchJSONCodec {
    func decodeEnvelope(from text: String) throws -> GraphPatchEnvelope {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(GraphPatchEnvelope.self, from: data)
    }

    func decodeGuideExportEnvelope(from text: String) throws -> GuideExportEnvelope {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(GuideExportEnvelope.self, from: data)
    }

    func encodeGraphExport(diagram: CustomCausalDiagram, aliasOverrides: [GardenAliasOverride]) throws -> String {
        let payload = GraphExportPayload(
            graphVersion: diagram.graphVersion,
            baseGraphVersion: diagram.baseGraphVersion,
            lastModified: diagram.lastModified,
            graphData: diagram.graphData,
            aliasOverrides: aliasOverrides
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    func encodeGuideExportEnvelope(_ envelope: GuideExportEnvelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        return String(decoding: data, as: UTF8.self)
    }

    func decodeErrorMessage(for error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .dataCorrupted(let context):
                return "Data corrupted at \(codingPath(context.codingPath)): \(context.debugDescription)"
            case .keyNotFound(let key, let context):
                let path = codingPath(context.codingPath + [key])
                return "Missing key at \(path): \(context.debugDescription)"
            case .typeMismatch(_, let context):
                return "Type mismatch at \(codingPath(context.codingPath)): \(context.debugDescription)"
            case .valueNotFound(_, let context):
                return "Missing value at \(codingPath(context.codingPath)): \(context.debugDescription)"
            @unknown default:
                return "Failed to decode payload."
            }
        }

        return error.localizedDescription
    }

    private func codingPath(_ codingPath: [CodingKey]) -> String {
        if codingPath.isEmpty {
            return "root"
        }
        return codingPath
            .map { key in
                key.intValue.map(String.init) ?? key.stringValue
            }
            .joined(separator: ".")
    }
}

private struct GraphExportPayload: Codable, Sendable {
    let graphVersion: String?
    let baseGraphVersion: String?
    let lastModified: String?
    let graphData: CausalGraphData
    let aliasOverrides: [GardenAliasOverride]
}
