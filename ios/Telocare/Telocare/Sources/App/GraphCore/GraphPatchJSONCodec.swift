import Foundation

struct GraphPatchJSONCodec {
    func decodeEnvelope(from text: String) throws -> GraphPatchEnvelope {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(GraphPatchEnvelope.self, from: data)
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
}

private struct GraphExportPayload: Codable, Sendable {
    let graphVersion: String?
    let baseGraphVersion: String?
    let lastModified: String?
    let graphData: CausalGraphData
    let aliasOverrides: [GardenAliasOverride]
}
