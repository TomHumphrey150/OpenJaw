import Foundation

struct FirstPartyContentBundle: Equatable, Sendable {
    let graphData: CausalGraphData?
    let interventionsCatalog: InterventionsCatalog
    let outcomesMetadata: OutcomesMetadata

    static let empty = FirstPartyContentBundle(
        graphData: nil,
        interventionsCatalog: .empty,
        outcomesMetadata: .empty
    )
}

struct InterventionsCatalog: Codable, Equatable, Sendable {
    let interventions: [InterventionDefinition]

    static let empty = InterventionsCatalog(interventions: [])
}

struct InterventionDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let detailedDescription: String?
    let evidenceLevel: String?
    let evidenceSummary: String?
    let citationIds: [String]?
    let externalLink: String?
    let defaultOrder: Int?

    var citations: [String] {
        citationIds ?? []
    }
}

struct OutcomesMetadata: Codable, Equatable, Sendable {
    let metrics: [OutcomeMetricDefinition]
    let nodes: [OutcomeNodeMetadata]
    let updatedAt: String?

    static let empty = OutcomesMetadata(metrics: [], nodes: [], updatedAt: nil)
}

struct OutcomeMetricDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let unit: String
    let direction: String
    let description: String
}

struct OutcomeNodeMetadata: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let styleClass: String
    let evidence: String?
    let stat: String?
    let citation: String?
    let mechanism: String?
}
