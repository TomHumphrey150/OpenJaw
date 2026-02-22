import Foundation

struct DashboardSnapshotBuilder {
    func build(
        from document: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle = .empty
    ) -> DashboardSnapshot {
        let graphData = graphData(
            from: document,
            fallbackGraph: firstPartyContent.graphData
        )
        let canonicalLookup = CanonicalInterventionLookup(catalog: firstPartyContent.interventionsCatalog)
        let canonicalData = CanonicalizedInterventionData(document: document, lookup: canonicalLookup)
        let outcomes = outcomeSummary(from: document, canonicalData: canonicalData)
        let outcomeRecords = outcomeRecords(from: document)
        let outcomesMetadata = firstPartyContent.outcomesMetadata
        let situation = situationSummary(from: graphData)
        let inputs = inputStatus(
            canonicalData: canonicalData,
            graphData: graphData,
            interventionsCatalog: firstPartyContent.interventionsCatalog
        )

        return DashboardSnapshot(
            outcomes: outcomes,
            outcomeRecords: outcomeRecords,
            outcomesMetadata: outcomesMetadata,
            situation: situation,
            inputs: inputs
        )
    }

    func graphData(from document: UserDataDocument, fallbackGraph: CausalGraphData? = nil) -> CausalGraphData {
        document.customCausalDiagram?.graphData
            ?? fallbackGraph
            ?? CanonicalGraphLoader.loadGraphOrFallback()
    }

    private func outcomeSummary(
        from document: UserDataDocument,
        canonicalData: CanonicalizedInterventionData
    ) -> OutcomeSummary {
        let sortedNights = document.nightOutcomes.sorted { $0.nightId > $1.nightId }
        let currentRate = sortedNights.first?.microArousalRatePerHour
        let previousRate = sortedNights.dropFirst().first?.microArousalRatePerHour

        let burdenTrendPercent = Self.burdenTrendPercent(current: currentRate, previous: previousRate)

        let recentKeys = canonicalData.dailyCheckIns.keys.sorted(by: >).prefix(7)
        let activeDays = recentKeys.filter { !(canonicalData.dailyCheckIns[$0] ?? []).isEmpty }.count
        let shieldScore = Int((Double(activeDays) / 7.0) * 100.0)

        let topContributor = canonicalData.habitClassifications.first(where: { $0.status == .harmful })?.interventionId
            ?? canonicalData.habitClassifications.first(where: { $0.status == .helpful })?.interventionId
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

    private func inputStatus(
        canonicalData: CanonicalizedInterventionData,
        graphData: CausalGraphData,
        interventionsCatalog: InterventionsCatalog
    ) -> [InputStatus] {
        let recentKeys = canonicalData.dailyCheckIns.keys.sorted(by: >)
        let latestBinaryKey = recentKeys.first
        let recentWindow = Array(recentKeys.prefix(7))
        let latestDoseKey = canonicalData.dailyDoseProgress.keys.sorted(by: >).first

        let hiddenInterventionIDs = Set(canonicalData.hiddenInterventions)
        let classificationByID = Dictionary(
            uniqueKeysWithValues: canonicalData.habitClassifications.map {
                ($0.interventionId, $0.status)
            }
        )
        let nodeByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data) })

        let orderedInterventions = interventionInventory(
            canonicalData: canonicalData,
            graphData: graphData,
            interventionsCatalog: interventionsCatalog
        )

        if orderedInterventions.isEmpty {
            return []
        }

        return orderedInterventions.map { intervention in
            let graphNode = intervention.graphNodeID.flatMap { nodeByID[$0] } ?? nodeByID[intervention.id]
            let classificationText = classificationByID[intervention.id].map(humanizeClassification)
            let appleHealthConnection = canonicalData.appleHealthConnections[intervention.id]

            switch intervention.trackingMode {
            case .binary:
                let daysOn = recentWindow.reduce(into: 0) { count, key in
                    if canonicalData.dailyCheckIns[key]?.contains(intervention.id) == true {
                        count += 1
                    }
                }

                let latestIncludes = latestBinaryKey.flatMap {
                    canonicalData.dailyCheckIns[$0]?.contains(intervention.id)
                } ?? false

                let statusText: String
                if latestIncludes {
                    statusText = "Checked today"
                } else if daysOn > 0 {
                    statusText = "\(daysOn)/7 days"
                } else {
                    statusText = "Not checked yet"
                }

                return InputStatus(
                    id: intervention.id,
                    name: intervention.name,
                    trackingMode: .binary,
                    statusText: statusText,
                    completion: min(1.0, Double(daysOn) / 7.0),
                    isCheckedToday: latestIncludes,
                    doseState: nil,
                    graphNodeID: intervention.graphNodeID ?? intervention.id,
                    classificationText: classificationText,
                    isHidden: hiddenInterventionIDs.contains(intervention.id),
                    evidenceLevel: intervention.evidenceLevel ?? graphNode?.tooltip?.evidence,
                    evidenceSummary: intervention.evidenceSummary ?? graphNode?.tooltip?.mechanism,
                    detailedDescription: intervention.detailedDescription,
                    citationIDs: intervention.citationIDs,
                    externalLink: intervention.externalLink,
                    appleHealthState: nil
                )

            case .dose:
                guard let doseConfig = intervention.doseConfig else {
                    return InputStatus(
                        id: intervention.id,
                        name: intervention.name,
                        trackingMode: .binary,
                        statusText: "Not checked yet",
                        completion: 0,
                        isCheckedToday: false,
                        doseState: nil,
                        graphNodeID: intervention.graphNodeID ?? intervention.id,
                        classificationText: classificationText,
                        isHidden: hiddenInterventionIDs.contains(intervention.id),
                        evidenceLevel: intervention.evidenceLevel ?? graphNode?.tooltip?.evidence,
                        evidenceSummary: intervention.evidenceSummary ?? graphNode?.tooltip?.mechanism,
                        detailedDescription: intervention.detailedDescription,
                        citationIDs: intervention.citationIDs,
                        externalLink: intervention.externalLink,
                        appleHealthState: nil
                    )
                }

                let settings = canonicalData.interventionDoseSettings[intervention.id]
                let goal = max(1, settings?.dailyGoal ?? doseConfig.defaultDailyGoal)
                let increment = max(1, settings?.increment ?? doseConfig.defaultIncrement)
                let manualValue = max(
                    0,
                    latestDoseKey.flatMap { canonicalData.dailyDoseProgress[$0]?[intervention.id] } ?? 0
                )
                let doseState = InputDoseState(
                    manualValue: manualValue,
                    healthValue: nil,
                    goal: goal,
                    increment: increment,
                    unit: doseConfig.unit
                )
                let appleHealthState = inputAppleHealthState(
                    intervention: intervention,
                    connection: appleHealthConnection
                )

                return InputStatus(
                    id: intervention.id,
                    name: intervention.name,
                    trackingMode: .dose,
                    statusText: doseStatusText(for: doseState),
                    completion: doseState.completionClamped,
                    isCheckedToday: doseState.isGoalMet,
                    doseState: doseState,
                    graphNodeID: intervention.graphNodeID ?? intervention.id,
                    classificationText: classificationText,
                    isHidden: hiddenInterventionIDs.contains(intervention.id),
                    evidenceLevel: intervention.evidenceLevel ?? graphNode?.tooltip?.evidence,
                    evidenceSummary: intervention.evidenceSummary ?? graphNode?.tooltip?.mechanism,
                    detailedDescription: intervention.detailedDescription,
                    citationIDs: intervention.citationIDs,
                    externalLink: intervention.externalLink,
                    appleHealthState: appleHealthState
                )
            }
        }
    }

    private func inputAppleHealthState(
        intervention: InterventionItem,
        connection: AppleHealthConnection?
    ) -> InputAppleHealthState? {
        guard intervention.appleHealthAvailable else {
            return nil
        }

        let isConnected = connection?.isConnected ?? false
        let status = connection?.lastSyncStatus ?? (isConnected ? .syncing : .disconnected)
        return InputAppleHealthState(
            available: true,
            connected: isConnected,
            syncStatus: status,
            todayHealthValue: nil,
            lastSyncAt: connection?.lastSyncAt,
            config: intervention.appleHealthConfig
        )
    }

    private func interventionInventory(
        canonicalData: CanonicalizedInterventionData,
        graphData: CausalGraphData,
        interventionsCatalog: InterventionsCatalog
    ) -> [InterventionItem] {
        let checkInIDs = Set(canonicalData.dailyCheckIns.values.flatMap { $0 })
        let classificationIDs = Set(canonicalData.habitClassifications.map { $0.interventionId })
        let ratingIDs = Set(canonicalData.interventionRatings.map { $0.interventionId })
        let doseProgressIDs = Set(canonicalData.dailyDoseProgress.values.flatMap { $0.keys })
        let settingsIDs = Set(canonicalData.interventionDoseSettings.keys)
        let appleHealthConnectionIDs = Set(canonicalData.appleHealthConnections.keys)

        let additionalIDs = checkInIDs
            .union(classificationIDs)
            .union(ratingIDs)
            .union(doseProgressIDs)
            .union(settingsIDs)
            .union(appleHealthConnectionIDs)

        if !interventionsCatalog.interventions.isEmpty {
            let fromCatalog = interventionsCatalog.interventions
                .sorted(by: Self.compareInterventionDefinitionOrder)
                .map { intervention in
                    InterventionItem(
                        id: intervention.id,
                        name: intervention.name,
                        trackingMode: intervention.trackingType == .dose ? .dose : .binary,
                        doseConfig: intervention.doseConfig,
                        graphNodeID: intervention.graphNodeId,
                        evidenceLevel: intervention.evidenceLevel,
                        evidenceSummary: intervention.evidenceSummary,
                        detailedDescription: intervention.detailedDescription,
                        citationIDs: intervention.citations,
                        externalLink: intervention.externalLink,
                        appleHealthAvailable: intervention.appleHealthAvailable ?? false,
                        appleHealthConfig: intervention.appleHealthConfig
                    )
                }

            var seen = Set<String>()
            var ordered: [InterventionItem] = []

            for intervention in fromCatalog where seen.insert(intervention.id).inserted {
                ordered.append(intervention)
            }

            let extras = additionalIDs.subtracting(seen).sorted()
            for id in extras {
                ordered.append(
                    InterventionItem(
                        id: id,
                        name: humanizeInterventionID(id),
                        trackingMode: .binary,
                        doseConfig: nil,
                        graphNodeID: id,
                        evidenceLevel: nil,
                        evidenceSummary: nil,
                        detailedDescription: nil,
                        citationIDs: [],
                        externalLink: nil,
                        appleHealthAvailable: false,
                        appleHealthConfig: nil
                    )
                )
            }

            return ordered
        }

        let fromGraph = graphData.nodes.compactMap { node -> InterventionItem? in
            guard node.data.styleClass == "intervention" else {
                return nil
            }

            return InterventionItem(
                id: node.data.id,
                name: Self.firstLine(in: node.data.label),
                trackingMode: .binary,
                doseConfig: nil,
                graphNodeID: node.data.id,
                evidenceLevel: node.data.tooltip?.evidence,
                evidenceSummary: node.data.tooltip?.mechanism,
                detailedDescription: nil,
                citationIDs: node.data.tooltip?.citation.map { [$0] } ?? [],
                externalLink: nil,
                appleHealthAvailable: false,
                appleHealthConfig: nil
            )
        }

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
                    name: humanizeInterventionID(id),
                    trackingMode: .binary,
                    doseConfig: nil,
                    graphNodeID: id,
                    evidenceLevel: nil,
                    evidenceSummary: nil,
                    detailedDescription: nil,
                    citationIDs: [],
                    externalLink: nil,
                    appleHealthAvailable: false,
                    appleHealthConfig: nil
                )
            )
        }

        return ordered
    }

    private func doseStatusText(for state: InputDoseState) -> String {
        let value = formattedDoseValue(state.value)
        let goal = formattedDoseValue(state.goal)
        let percent = Int((state.completionRaw * 100).rounded())
        return "\(value)/\(goal) \(state.unit.displayName) today (\(percent)%)"
    }

    private func formattedDoseValue(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
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

    private static func compareInterventionDefinitionOrder(
        lhs: InterventionDefinition,
        rhs: InterventionDefinition
    ) -> Bool {
        let lhsOrder = lhs.defaultOrder ?? Int.max
        let rhsOrder = rhs.defaultOrder ?? Int.max

        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }

        return lhs.id < rhs.id
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
    let trackingMode: InputTrackingMode
    let doseConfig: DoseConfig?
    let graphNodeID: String?
    let evidenceLevel: String?
    let evidenceSummary: String?
    let detailedDescription: String?
    let citationIDs: [String]
    let externalLink: String?
    let appleHealthAvailable: Bool
    let appleHealthConfig: AppleHealthConfig?
}

private struct CanonicalInterventionLookup {
    let canonicalByID: [String: String]

    init(catalog: InterventionsCatalog) {
        var map: [String: String] = [:]
        for definition in catalog.interventions {
            let aliases = [definition.id] + definition.legacyIDs
            for alias in aliases {
                let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    continue
                }

                if map[normalized] == nil {
                    map[normalized] = definition.id
                }
            }
        }
        canonicalByID = map
    }

    func canonicalID(for id: String) -> String {
        canonicalByID[id] ?? id
    }
}

private struct CanonicalizedInterventionData {
    let dailyCheckIns: [String: [String]]
    let dailyDoseProgress: [String: [String: Double]]
    let interventionDoseSettings: [String: DoseSettings]
    let appleHealthConnections: [String: AppleHealthConnection]
    let hiddenInterventions: [String]
    let interventionRatings: [InterventionRating]
    let habitClassifications: [HabitClassification]

    init(document: UserDataDocument, lookup: CanonicalInterventionLookup) {
        dailyCheckIns = Self.canonicalizedDailyCheckIns(document.dailyCheckIns, lookup: lookup)
        dailyDoseProgress = Self.canonicalizedDailyDoseProgress(document.dailyDoseProgress, lookup: lookup)
        interventionDoseSettings = Self.canonicalizedDoseSettings(document.interventionDoseSettings, lookup: lookup)
        appleHealthConnections = Self.canonicalizedAppleHealthConnections(document.appleHealthConnections, lookup: lookup)
        hiddenInterventions = Self.canonicalizedIDs(document.hiddenInterventions, lookup: lookup)
        interventionRatings = Self.canonicalizedInterventionRatings(document.interventionRatings, lookup: lookup)
        habitClassifications = Self.canonicalizedHabitClassifications(document.habitClassifications, lookup: lookup)
    }

    private static func canonicalizedDailyCheckIns(
        _ current: [String: [String]],
        lookup: CanonicalInterventionLookup
    ) -> [String: [String]] {
        var next: [String: [String]] = [:]
        for (dateKey, ids) in current {
            next[dateKey] = canonicalizedIDs(ids, lookup: lookup)
        }
        return next
    }

    private static func canonicalizedDailyDoseProgress(
        _ current: [String: [String: Double]],
        lookup: CanonicalInterventionLookup
    ) -> [String: [String: Double]] {
        var next: [String: [String: Double]] = [:]

        for (dateKey, progress) in current {
            var normalized: [String: Double] = [:]
            for (id, value) in progress {
                let canonicalID = lookup.canonicalID(for: id)
                normalized[canonicalID] = (normalized[canonicalID] ?? 0) + value
            }
            next[dateKey] = normalized
        }

        return next
    }

    private static func canonicalizedDoseSettings(
        _ current: [String: DoseSettings],
        lookup: CanonicalInterventionLookup
    ) -> [String: DoseSettings] {
        var next: [String: DoseSettings] = [:]

        for (id, settings) in current {
            let canonicalID = lookup.canonicalID(for: id)
            next[canonicalID] = settings
        }

        return next
    }

    private static func canonicalizedAppleHealthConnections(
        _ current: [String: AppleHealthConnection],
        lookup: CanonicalInterventionLookup
    ) -> [String: AppleHealthConnection] {
        var next: [String: AppleHealthConnection] = [:]

        for (id, connection) in current {
            let canonicalID = lookup.canonicalID(for: id)
            next[canonicalID] = connection
        }

        return next
    }

    private static func canonicalizedInterventionRatings(
        _ current: [InterventionRating],
        lookup: CanonicalInterventionLookup
    ) -> [InterventionRating] {
        var seen = Set<String>()
        var ordered: [InterventionRating] = []

        for rating in current {
            let canonicalID = lookup.canonicalID(for: rating.interventionId)
            let normalized = InterventionRating(
                interventionId: canonicalID,
                effectiveness: rating.effectiveness,
                notes: rating.notes,
                lastUpdated: rating.lastUpdated
            )

            if seen.insert(canonicalID).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private static func canonicalizedHabitClassifications(
        _ current: [HabitClassification],
        lookup: CanonicalInterventionLookup
    ) -> [HabitClassification] {
        var seen = Set<String>()
        var ordered: [HabitClassification] = []

        for classification in current {
            let canonicalID = lookup.canonicalID(for: classification.interventionId)
            let normalized = HabitClassification(
                interventionId: canonicalID,
                status: classification.status,
                nightsOn: classification.nightsOn,
                nightsOff: classification.nightsOff,
                microArousalDeltaPct: classification.microArousalDeltaPct,
                morningStateDelta: classification.morningStateDelta,
                windowQuality: classification.windowQuality,
                updatedAt: classification.updatedAt
            )

            if seen.insert(canonicalID).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private static func canonicalizedIDs(
        _ ids: [String],
        lookup: CanonicalInterventionLookup
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for id in ids {
            let canonicalID = lookup.canonicalID(for: id)
            if seen.insert(canonicalID).inserted {
                ordered.append(canonicalID)
            }
        }

        return ordered
    }
}
