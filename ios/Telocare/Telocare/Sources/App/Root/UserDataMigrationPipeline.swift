import Foundation

protocol UserDataMigrationPipeline {
    func run(
        fetchedDocument: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle
    ) -> UserDataMigrationPipelineResult
}

struct UserDataMigrationPipelineResult {
    let document: UserDataDocument
    let fallbackGraph: CausalGraphData
    let canonicalBackfillDiagram: CustomCausalDiagram?
    let dormantGraphMigrationDiagram: CustomCausalDiagram?
    let sleepAttributionMigrationPatch: UserDataPatch?
}

struct DefaultUserDataMigrationPipeline: UserDataMigrationPipeline {
    func run(
        fetchedDocument: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle
    ) -> UserDataMigrationPipelineResult {
        let fallbackGraph = firstPartyContent.graphData ?? CanonicalGraphLoader.loadGraphOrFallback()
        let hydratedDocument = withCanonicalGraphIfMissing(
            fetchedDocument,
            fallbackGraph: fallbackGraph
        )
        let graphMigratedDocument = withLegacyDormantGraphDeactivationMigrationIfNeeded(hydratedDocument)
        let migratedDocument = withWakeDaySleepAttributionMigrationIfNeeded(
            graphMigratedDocument,
            interventionsCatalog: firstPartyContent.interventionsCatalog
        )

        let canonicalBackfillDiagram: CustomCausalDiagram?
        if fetchedDocument.customCausalDiagram == nil {
            canonicalBackfillDiagram = migratedDocument.customCausalDiagram
        } else {
            canonicalBackfillDiagram = nil
        }

        let dormantGraphMigrationDiagram: CustomCausalDiagram?
        if fetchedDocument.customCausalDiagram != nil,
            hydratedDocument.customCausalDiagram != graphMigratedDocument.customCausalDiagram {
            dormantGraphMigrationDiagram = graphMigratedDocument.customCausalDiagram
        } else {
            dormantGraphMigrationDiagram = nil
        }

        let sleepAttributionMigrationPatch: UserDataPatch?
        if shouldPersistWakeDaySleepAttributionMigration(
            from: graphMigratedDocument,
            migrated: migratedDocument
        ) {
            sleepAttributionMigrationPatch = .sleepAttributionMigration(
                dailyDoseProgress: migratedDocument.dailyDoseProgress,
                nightOutcomes: migratedDocument.nightOutcomes,
                morningStates: migratedDocument.morningStates
            )
        } else {
            sleepAttributionMigrationPatch = nil
        }

        return UserDataMigrationPipelineResult(
            document: migratedDocument,
            fallbackGraph: fallbackGraph,
            canonicalBackfillDiagram: canonicalBackfillDiagram,
            dormantGraphMigrationDiagram: dormantGraphMigrationDiagram,
            sleepAttributionMigrationPatch: sleepAttributionMigrationPatch
        )
    }

    private func withCanonicalGraphIfMissing(
        _ document: UserDataDocument,
        fallbackGraph: CausalGraphData
    ) -> UserDataDocument {
        guard document.customCausalDiagram == nil else {
            return document
        }

        let graphData = Self.seedLegacyDormantGraphDeactivationIfNeeded(fallbackGraph) ?? fallbackGraph
        let canonicalDiagram = CustomCausalDiagram(
            graphData: graphData,
            lastModified: Self.timestampNow()
        )

        return document.withCustomCausalDiagram(canonicalDiagram)
    }

    private func withLegacyDormantGraphDeactivationMigrationIfNeeded(_ document: UserDataDocument) -> UserDataDocument {
        guard let customCausalDiagram = document.customCausalDiagram else {
            return document
        }

        guard let migratedGraphData = Self.seedLegacyDormantGraphDeactivationIfNeeded(customCausalDiagram.graphData) else {
            return document
        }

        let migratedDiagram = CustomCausalDiagram(
            graphData: migratedGraphData,
            lastModified: Self.timestampNow()
        )
        return document.withCustomCausalDiagram(migratedDiagram)
    }

    private func withWakeDaySleepAttributionMigrationIfNeeded(
        _ document: UserDataDocument,
        interventionsCatalog: InterventionsCatalog
    ) -> UserDataDocument {
        guard !document.wakeDaySleepAttributionMigrated else {
            return document
        }

        let sleepInterventionIDs = Self.sleepInterventionIDs(from: interventionsCatalog)
        let migratedDailyDoseProgress = Self.shiftSleepDoseProgress(
            document.dailyDoseProgress,
            sleepInterventionIDs: sleepInterventionIDs
        )
        let migratedNightOutcomes = Self.shiftNightOutcomes(document.nightOutcomes)
        let migratedMorningStates = Self.shiftMorningStates(document.morningStates)

        let hasChanges =
            migratedDailyDoseProgress != document.dailyDoseProgress
            || migratedNightOutcomes != document.nightOutcomes
            || migratedMorningStates != document.morningStates
        guard hasChanges else {
            return document
        }

        return document.withSleepAttributionMigration(
            dailyDoseProgress: migratedDailyDoseProgress,
            nightOutcomes: migratedNightOutcomes,
            morningStates: migratedMorningStates,
            wakeDaySleepAttributionMigrated: true
        )
    }

    private func shouldPersistWakeDaySleepAttributionMigration(
        from fetched: UserDataDocument,
        migrated: UserDataDocument
    ) -> Bool {
        fetched.wakeDaySleepAttributionMigrated != migrated.wakeDaySleepAttributionMigrated
            || fetched.dailyDoseProgress != migrated.dailyDoseProgress
            || fetched.nightOutcomes != migrated.nightOutcomes
            || fetched.morningStates != migrated.morningStates
    }

    private static func seedLegacyDormantGraphDeactivationIfNeeded(_ graphData: CausalGraphData) -> CausalGraphData? {
        if hasExplicitGraphDeactivationState(graphData) {
            return nil
        }

        let dormantNodeIDs = Set(
            graphData.nodes
                .map(\.data)
                .filter(isLegacyDormantNode)
                .map(\.id)
        )

        guard !dormantNodeIDs.isEmpty else {
            return nil
        }

        let nextNodes = graphData.nodes.map { node in
            guard dormantNodeIDs.contains(node.data.id) else {
                return node
            }

            return GraphNodeElement(
                data: GraphNodeData(
                    id: node.data.id,
                    label: node.data.label,
                    styleClass: node.data.styleClass,
                    confirmed: node.data.confirmed,
                    tier: node.data.tier,
                    tooltip: node.data.tooltip,
                    isDeactivated: true,
                    parentIds: node.data.parentIds,
                    parentId: node.data.parentId,
                    isExpanded: node.data.isExpanded
                )
            )
        }

        let nextEdges = graphData.edges.map { edge in
            guard dormantNodeIDs.contains(edge.data.source) || dormantNodeIDs.contains(edge.data.target) else {
                return edge
            }

            return GraphEdgeElement(
                data: GraphEdgeData(
                    source: edge.data.source,
                    target: edge.data.target,
                    label: edge.data.label,
                    edgeType: edge.data.edgeType,
                    edgeColor: edge.data.edgeColor,
                    tooltip: edge.data.tooltip,
                    isDeactivated: true
                )
            )
        }

        return CausalGraphData(
            nodes: nextNodes,
            edges: nextEdges
        )
    }

    private static func hasExplicitGraphDeactivationState(_ graphData: CausalGraphData) -> Bool {
        if graphData.nodes.contains(where: { $0.data.isDeactivated != nil }) {
            return true
        }

        return graphData.edges.contains(where: { $0.data.isDeactivated != nil })
    }

    private static func isLegacyDormantNode(_ node: GraphNodeData) -> Bool {
        guard let confirmed = node.confirmed?.lowercased() else {
            return false
        }

        return confirmed == "no" || confirmed == "inactive" || confirmed == "external"
    }

    private static func sleepInterventionIDs(from catalog: InterventionsCatalog) -> Set<String> {
        Set(
            catalog.interventions.compactMap { intervention in
                guard let config = intervention.appleHealthConfig else {
                    return nil
                }

                if config.identifier == .sleepAnalysis {
                    return intervention.id
                }

                if config.dayAttribution == .previousNightNoonCutoff {
                    return intervention.id
                }

                return nil
            }
        )
    }

    private static func shiftSleepDoseProgress(
        _ dailyDoseProgress: [String: [String: Double]],
        sleepInterventionIDs: Set<String>
    ) -> [String: [String: Double]] {
        guard !sleepInterventionIDs.isEmpty else {
            return dailyDoseProgress
        }

        var migrated = dailyDoseProgress

        for (dateKey, dosesByIntervention) in dailyDoseProgress {
            let shiftedDateKey = shiftedDateKeyByOneDay(dateKey)
            guard shiftedDateKey != dateKey else {
                continue
            }

            let sleepEntries = dosesByIntervention.filter { sleepInterventionIDs.contains($0.key) }
            guard !sleepEntries.isEmpty else {
                continue
            }

            var sourceDoses = migrated[dateKey] ?? [:]
            var targetDoses = migrated[shiftedDateKey] ?? [:]

            for (interventionID, value) in sleepEntries {
                sourceDoses.removeValue(forKey: interventionID)
                let existingValue = targetDoses[interventionID] ?? 0
                targetDoses[interventionID] = max(existingValue, value)
            }

            if sourceDoses.isEmpty {
                migrated.removeValue(forKey: dateKey)
            } else {
                migrated[dateKey] = sourceDoses
            }
            migrated[shiftedDateKey] = targetDoses
        }

        return migrated
    }

    private static func shiftNightOutcomes(_ nightOutcomes: [NightOutcome]) -> [NightOutcome] {
        var outcomesByNightID: [String: NightOutcome] = [:]

        for outcome in nightOutcomes {
            let shiftedNightID = shiftedDateKeyByOneDay(outcome.nightId)
            guard shiftedNightID != outcome.nightId else {
                outcomesByNightID[outcome.nightId] = preferredNightOutcome(
                    existing: outcomesByNightID[outcome.nightId],
                    candidate: outcome
                )
                continue
            }

            let shiftedOutcome = NightOutcome(
                nightId: shiftedNightID,
                microArousalCount: outcome.microArousalCount,
                microArousalRatePerHour: outcome.microArousalRatePerHour,
                confidence: outcome.confidence,
                totalSleepMinutes: outcome.totalSleepMinutes,
                source: outcome.source,
                createdAt: outcome.createdAt
            )
            outcomesByNightID[shiftedNightID] = preferredNightOutcome(
                existing: outcomesByNightID[shiftedNightID],
                candidate: shiftedOutcome
            )
        }

        return outcomesByNightID.values.sorted { $0.nightId > $1.nightId }
    }

    private static func preferredNightOutcome(
        existing: NightOutcome?,
        candidate: NightOutcome
    ) -> NightOutcome {
        guard let existing else {
            return candidate
        }

        if candidate.createdAt >= existing.createdAt {
            return candidate
        }

        return existing
    }

    private static func shiftMorningStates(_ morningStates: [MorningState]) -> [MorningState] {
        var statesByNightID: [String: MorningState] = [:]

        for state in morningStates {
            let shiftedNightID = shiftedDateKeyByOneDay(state.nightId)
            guard shiftedNightID != state.nightId else {
                statesByNightID[state.nightId] = preferredMorningState(
                    existing: statesByNightID[state.nightId],
                    candidate: state
                )
                continue
            }

            let shiftedState = MorningState(
                nightId: shiftedNightID,
                globalSensation: state.globalSensation,
                neckTightness: state.neckTightness,
                jawSoreness: state.jawSoreness,
                earFullness: state.earFullness,
                healthAnxiety: state.healthAnxiety,
                stressLevel: state.stressLevel,
                morningHeadache: state.morningHeadache,
                dryMouth: state.dryMouth,
                createdAt: state.createdAt
            )
            statesByNightID[shiftedNightID] = preferredMorningState(
                existing: statesByNightID[shiftedNightID],
                candidate: shiftedState
            )
        }

        return statesByNightID.values.sorted { $0.nightId > $1.nightId }
    }

    private static func preferredMorningState(
        existing: MorningState?,
        candidate: MorningState
    ) -> MorningState {
        guard let existing else {
            return candidate
        }

        if candidate.createdAt >= existing.createdAt {
            return candidate
        }

        return existing
    }

    private static func shiftedDateKeyByOneDay(_ dateKey: String) -> String {
        let parts = dateKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return dateKey
        }

        guard
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return dateKey
        }

        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return dateKey
        }
        guard let shiftedDate = calendar.date(byAdding: .day, value: 1, to: date) else {
            return dateKey
        }

        let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shiftedDate)
        guard
            let shiftedYear = shiftedComponents.year,
            let shiftedMonth = shiftedComponents.month,
            let shiftedDay = shiftedComponents.day
        else {
            return dateKey
        }

        return String(format: "%04d-%02d-%02d", shiftedYear, shiftedMonth, shiftedDay)
    }

    private static func timestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
