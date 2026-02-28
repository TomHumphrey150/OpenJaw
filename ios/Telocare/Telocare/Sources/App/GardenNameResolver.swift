import Foundation

struct LayerSignature: Hashable, Equatable, Sendable {
    let rawValue: String

    init(nodeIDs: [String]) {
        rawValue = nodeIDs.sorted().joined(separator: "|")
    }
}

struct GardenAliasCatalog: Sendable {
    let nodeAliasByID: [String: String]
    let layerAliasBySignature: [LayerSignature: String]

    static let `default` = GardenAliasCatalog(
        nodeAliasByID: [
            "ACID": "Acid Exposure",
            "AIRWAY_OBS": "Airway Obstruction",
            "CATECHOL": "Adrenaline Load",
            "CERVICAL": "Cervical Strain",
            "CORTISOL": "Cortisol Load",
            "EXTERNAL_TRIGGERS": "External Triggers",
            "FHP": "Forward Head Posture",
            "GABA_DEF": "GABA Support",
            "GERD": "Reflux Pressure",
            "HEALTH_ANXIETY": "Health Anxiety",
            "HYOID": "Tongue-Hyoid Tone",
            "MG_DEF": "Magnesium Status",
            "MICRO": "Microarousal Drive",
            "NECK_TIGHTNESS": "Neck Tension",
            "NEG_PRESSURE": "Negative Pressure",
            "OSA": "Sleep Breathing",
            "RMMA": "Clenching Drive",
            "SALIVA": "Saliva Protection",
            "SLEEP_DEP": "Sleep Debt",
            "SSRI": "Medication Effects",
            "STRESS": "Stress Load",
            "SYMPATHETIC": "Sympathetic Drive",
            "TLESR": "LES Relaxation",
            "TMD": "Jaw Joint Strain",
            "TOOTH": "Tooth Protection",
            "VAGAL": "Vagal Tone",
            "VIT_D": "Vitamin D Status",
        ],
        layerAliasBySignature: [
            LayerSignature(nodeIDs: ["STRESS", "SLEEP_DEP", "SYMPATHETIC"]): "Arousal Loop",
            LayerSignature(nodeIDs: ["GERD", "ACID", "TLESR"]): "Reflux Loop",
            LayerSignature(nodeIDs: ["RMMA", "TMD", "NECK_TIGHTNESS"]): "Jaw-Neck Loop",
            LayerSignature(nodeIDs: ["AIRWAY_OBS", "OSA", "NEG_PRESSURE"]): "Airway Loop",
        ]
    )
}

struct GardenNameResolver {
    private let catalog: GardenAliasCatalog
    private let overrideTitleBySignature: [String: String]

    init(
        catalog: GardenAliasCatalog = .default,
        overrides: [GardenAliasOverride] = []
    ) {
        self.catalog = catalog
        overrideTitleBySignature = Dictionary(uniqueKeysWithValues: overrides.map { ($0.signature, $0.title) })
    }

    func withOverrides(_ overrides: [GardenAliasOverride]) -> GardenNameResolver {
        GardenNameResolver(
            catalog: catalog,
            overrides: overrides
        )
    }

    func nodeTitle(nodeID: String, fallbackLabel: String?) -> String {
        if let alias = catalog.nodeAliasByID[nodeID], !alias.isEmpty {
            return alias
        }

        if let fallbackLabel {
            let firstLineLabel = firstLine(of: fallbackLabel)
            if !firstLineLabel.isEmpty {
                return firstLineLabel
            }
        }

        return nodeID
    }

    func layerTitle(nodePath: [String], labelByID: [String: String]) -> String {
        if nodePath.isEmpty {
            return "All Gardens"
        }

        let signature = LayerSignature(nodeIDs: nodePath)
        if let overrideTitle = overrideTitleBySignature[signature.rawValue], !overrideTitle.isEmpty {
            return overrideTitle
        }

        if nodePath.count == 1 {
            let nodeID = nodePath[0]
            return nodeTitle(nodeID: nodeID, fallbackLabel: labelByID[nodeID])
        }

        if nodePath.count == 2 {
            let names = nodePath.map { nodeID in
                nodeTitle(nodeID: nodeID, fallbackLabel: labelByID[nodeID])
            }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            return names.joined(separator: " + ")
        }

        if let layerAlias = catalog.layerAliasBySignature[signature], !layerAlias.isEmpty {
            return layerAlias
        }

        let sortedTitles = nodePath
            .sorted()
            .map { nodeID in
                nodeTitle(nodeID: nodeID, fallbackLabel: labelByID[nodeID])
            }
        let primary = sortedTitles.first ?? "Garden"
        return "\(primary) Network"
    }

    private func firstLine(of text: String) -> String {
        let firstSegment = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        return String(firstSegment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
