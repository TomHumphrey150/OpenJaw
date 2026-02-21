import Foundation

struct DashboardSnapshotBuilder {
    func build(from document: UserDataDocument) -> DashboardSnapshot {
        let graphData = graphData(from: document)
        let outcomes = outcomeSummary(from: document)
        let situation = situationSummary(from: graphData)
        let inputs = inputStatus(from: document)

        return DashboardSnapshot(
            outcomes: outcomes,
            situation: situation,
            inputs: inputs
        )
    }

    func graphData(from document: UserDataDocument) -> CausalGraphData {
        document.customCausalDiagram?.graphData ?? .defaultGraph
    }

    private func outcomeSummary(from document: UserDataDocument) -> OutcomeSummary {
        let sortedNights = document.nightOutcomes.sorted { $0.nightId > $1.nightId }
        let currentRate = sortedNights.first?.microArousalRatePerHour
        let previousRate = sortedNights.dropFirst().first?.microArousalRatePerHour

        let burdenTrendPercent = Self.burdenTrendPercent(current: currentRate, previous: previousRate)

        let recentKeys = document.dailyCheckIns.keys.sorted(by: >).prefix(7)
        let activeDays = recentKeys.filter { !(document.dailyCheckIns[$0] ?? []).isEmpty }.count
        let shieldScore = Int((Double(activeDays) / 7.0) * 100.0)

        let topContributor = document.habitClassifications.first(where: { $0.status == .harmful })?.interventionId
            ?? document.habitClassifications.first(where: { $0.status == .helpful })?.interventionId
            ?? "Reflux pathway"

        let confidence: String
        switch sortedNights.count {
        case 0...1:
            confidence = "Low"
        case 2...4:
            confidence = "Moderate"
        default:
            confidence = "High"
        }

        let normalizedShieldScore = max(0, min(100, shieldScore))

        return OutcomeSummary(
            shieldScore: normalizedShieldScore,
            burdenTrendPercent: burdenTrendPercent,
            topContributor: humanizeInterventionID(topContributor),
            confidence: confidence,
            burdenProgress: Double(normalizedShieldScore) / 100.0
        )
    }

    private func situationSummary(from graphData: CausalGraphData) -> SituationSummary {
        let focusNode = graphData.nodes.first(where: { $0.data.styleClass != "intervention" })?.data

        let focusedNode = focusNode.map { Self.firstLine(in: $0.label) } ?? "RMMA"
        let tierLabel = focusNode?.tier.map { "Tier \($0)" } ?? "Tier n/a"

        let visibleHotspots = graphData.nodes.filter {
            $0.data.styleClass == "symptom" || $0.data.confirmed == "no"
        }.count

        let nodeLabels = Dictionary(uniqueKeysWithValues: graphData.nodes.map {
            ($0.data.id, Self.firstLine(in: $0.data.label))
        })

        let topSource = graphData.edges
            .first(where: { $0.data.target == focusNode?.id })
            .flatMap { nodeLabels[$0.data.source] }
            ?? "Reflux pathway"

        return SituationSummary(
            focusedNode: focusedNode,
            tier: tierLabel,
            visibleHotspots: max(1, visibleHotspots),
            topSource: topSource
        )
    }

    private func inputStatus(from document: UserDataDocument) -> [InputStatus] {
        let recentKeys = document.dailyCheckIns.keys.sorted(by: >)
        let latestKey = recentKeys.first
        let recentWindow = Array(recentKeys.prefix(7))

        let uniqueIDs = Set(recentWindow.flatMap { document.dailyCheckIns[$0] ?? [] })
        if uniqueIDs.isEmpty {
            return [
                InputStatus(id: "ppi", name: "PPI", statusText: "Checked", completion: 0.90),
                InputStatus(id: "reflux_diet", name: "Reflux Diet", statusText: "Checked", completion: 0.76),
                InputStatus(id: "bed_elevation", name: "Bed Elevation", statusText: "1/7", completion: 0.30),
            ]
        }

        return uniqueIDs.sorted().prefix(6).map { interventionID in
            let daysOn = recentWindow.reduce(into: 0) { count, key in
                if document.dailyCheckIns[key]?.contains(interventionID) == true {
                    count += 1
                }
            }

            let latestIncludes = latestKey.flatMap { document.dailyCheckIns[$0]?.contains(interventionID) } ?? false

            return InputStatus(
                id: interventionID,
                name: humanizeInterventionID(interventionID),
                statusText: latestIncludes ? "Checked" : "\(daysOn)/7",
                completion: min(1.0, Double(daysOn) / 7.0)
            )
        }
    }

    private static func burdenTrendPercent(current: Double?, previous: Double?) -> Int {
        guard let current, let previous, previous != 0 else {
            return -11
        }

        let delta = ((current - previous) / previous) * 100.0
        return Int(delta.rounded())
    }

    private static func firstLine(in text: String) -> String {
        text.components(separatedBy: "\n").first ?? text
    }

    private func humanizeInterventionID(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_TX", with: "")
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
