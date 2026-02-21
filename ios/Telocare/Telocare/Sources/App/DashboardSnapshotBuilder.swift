import Foundation

struct DashboardSnapshotBuilder {
    func build(from document: UserDataDocument) -> DashboardSnapshot {
        let graphData = graphData(from: document)
        let outcomes = outcomeSummary(from: document)
        let outcomeRecords = outcomeRecords(from: document)
        let situation = situationSummary(from: graphData)
        let inputs = inputStatus(from: document, graphData: graphData)

        return DashboardSnapshot(
            outcomes: outcomes,
            outcomeRecords: outcomeRecords,
            situation: situation,
            inputs: inputs
        )
    }

    func graphData(from document: UserDataDocument) -> CausalGraphData {
        document.customCausalDiagram?.graphData ?? CanonicalGraphLoader.loadGraphOrFallback()
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

    private func outcomeRecords(from document: UserDataDocument) -> [OutcomeRecord] {
        document.nightOutcomes
            .sorted { $0.nightId > $1.nightId }
            .map { outcome in
                OutcomeRecord(
                    id: outcome.nightId,
                    microArousalRatePerHour: outcome.microArousalRatePerHour,
                    microArousalCount: outcome.microArousalCount,
                    confidence: outcome.confidence,
                    source: outcome.source
                )
            }
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

    private func inputStatus(from document: UserDataDocument, graphData: CausalGraphData) -> [InputStatus] {
        let recentKeys = document.dailyCheckIns.keys.sorted(by: >)
        let latestKey = recentKeys.first
        let recentWindow = Array(recentKeys.prefix(7))
        let hiddenInterventionIDs = Set(document.hiddenInterventions)
        let classificationByID = Dictionary(
            uniqueKeysWithValues: document.habitClassifications.map {
                ($0.interventionId, $0.status)
            }
        )
        let orderedInterventions = interventionInventory(from: document, graphData: graphData)

        if orderedInterventions.isEmpty {
            return []
        }

        return orderedInterventions.map { intervention in
            let daysOn = recentWindow.reduce(into: 0) { count, key in
                if document.dailyCheckIns[key]?.contains(intervention.id) == true {
                    count += 1
                }
            }

            let latestIncludes = latestKey.flatMap {
                document.dailyCheckIns[$0]?.contains(intervention.id)
            } ?? false

            let statusText: String
            if latestIncludes {
                statusText = "Checked today"
            } else if daysOn > 0 {
                statusText = "\(daysOn)/7 days"
            } else {
                statusText = "Not checked yet"
            }

            let classificationText = classificationByID[intervention.id].map(humanizeClassification)
            return InputStatus(
                id: intervention.id,
                name: intervention.name,
                statusText: statusText,
                completion: min(1.0, Double(daysOn) / 7.0),
                isCheckedToday: latestIncludes,
                classificationText: classificationText,
                isHidden: hiddenInterventionIDs.contains(intervention.id)
            )
        }
    }

    private func interventionInventory(from document: UserDataDocument, graphData: CausalGraphData) -> [InterventionItem] {
        let fromGraph = graphData.nodes.compactMap { node -> InterventionItem? in
            guard node.data.styleClass == "intervention" else {
                return nil
            }

            return InterventionItem(
                id: node.data.id,
                name: Self.firstLine(in: node.data.label)
            )
        }

        let checkInIDs = Set(document.dailyCheckIns.values.flatMap { $0 })
        let classificationIDs = Set(document.habitClassifications.map { $0.interventionId })
        let ratingIDs = Set(document.interventionRatings.map { $0.interventionId })
        let additionalIDs = checkInIDs
            .union(classificationIDs)
            .union(ratingIDs)

        var seen = Set<String>()
        var ordered: [InterventionItem] = []

        for intervention in fromGraph where seen.insert(intervention.id).inserted {
            ordered.append(intervention)
        }

        let extras = additionalIDs.subtracting(seen).sorted()
        for id in extras {
            ordered.append(
                InterventionItem(
                    id: id,
                    name: humanizeInterventionID(id)
                )
            )
        }

        return ordered
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

    private func humanizeClassification(_ status: HabitEffectStatus) -> String {
        switch status {
        case .helpful:
            return "Helpful"
        case .neutral:
            return "Neutral"
        case .harmful:
            return "Harmful"
        case .unknown:
            return "Unknown"
        }
    }
}

private struct InterventionItem {
    let id: String
    let name: String
}
