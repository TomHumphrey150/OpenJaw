import Foundation

protocol UserDataMigrationPipeline {
    func run(
        fetchedDocument: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle
    ) -> UserDataMigrationPipelineResult
}

struct UserDataMigrationPipelineResult {
    let document: UserDataDocument
    let canonicalBackfillDiagram: CustomCausalDiagram?
    let dormantGraphMigrationDiagram: CustomCausalDiagram?
    let sleepAttributionMigrationPatch: UserDataPatch?
}

struct DefaultUserDataMigrationPipeline: UserDataMigrationPipeline {
    func run(
        fetchedDocument: UserDataDocument,
        firstPartyContent: FirstPartyContentBundle
    ) -> UserDataMigrationPipelineResult {
        let canonicalGraph = firstPartyContent.graphData ?? CausalGraphData(nodes: [], edges: [])
        let hydratedDocument = withCanonicalGraphIfMissing(
            fetchedDocument,
            canonicalGraph: canonicalGraph
        )
        let dormantGraphMigratedDocument = withLegacyDormantGraphDeactivationMigrationIfNeeded(hydratedDocument)
        let graphMetadataMigratedDocument = withGraphMetadataMigrationIfNeeded(dormantGraphMigratedDocument)
        let resolvedPlanningPolicy = firstPartyContent.planningPolicy ?? .default
        let questionSetMigratedDocument = withProgressQuestionSetStateIfMissing(
            graphMetadataMigratedDocument,
            planningPolicy: resolvedPlanningPolicy
        )
        let questionSetBackfilledDocument = withProgressQuestionSetActiveQuestionsMigrationIfNeeded(
            questionSetMigratedDocument,
            planningPolicy: resolvedPlanningPolicy
        )
        let planningStateMigratedDocument = withPlanningStateDefaultsIfMissing(questionSetBackfilledDocument)
        let acutePillarMigratedDocument = withLegacyAcuteCustomPillarMigrationIfNeeded(
            planningStateMigratedDocument,
            interventionsCatalog: firstPartyContent.interventionsCatalog
        )
        let migratedDocument = withWakeDaySleepAttributionMigrationIfNeeded(
            acutePillarMigratedDocument,
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
            hydratedDocument.customCausalDiagram != graphMetadataMigratedDocument.customCausalDiagram {
            dormantGraphMigrationDiagram = graphMetadataMigratedDocument.customCausalDiagram
        } else {
            dormantGraphMigrationDiagram = nil
        }

        let sleepAttributionMigrationPatch: UserDataPatch?
        if shouldPersistWakeDaySleepAttributionMigration(
            from: acutePillarMigratedDocument,
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
            canonicalBackfillDiagram: canonicalBackfillDiagram,
            dormantGraphMigrationDiagram: dormantGraphMigrationDiagram,
            sleepAttributionMigrationPatch: sleepAttributionMigrationPatch
        )
    }

    private func withCanonicalGraphIfMissing(
        _ document: UserDataDocument,
        canonicalGraph: CausalGraphData
    ) -> UserDataDocument {
        guard document.customCausalDiagram == nil else {
            return document
        }

        let graphData = Self.seedLegacyDormantGraphDeactivationIfNeeded(canonicalGraph) ?? canonicalGraph
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

    private func withGraphMetadataMigrationIfNeeded(_ document: UserDataDocument) -> UserDataDocument {
        guard let customCausalDiagram = document.customCausalDiagram else {
            return document
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: customCausalDiagram.graphData.nodes.map { ($0.data.id, $0.data) })
        var edgeCountByCanonicalPrefix: [String: Int] = [:]
        var hasEdgeChanges = false
        let migratedEdges = customCausalDiagram.graphData.edges.map { edgeElement in
            let edge = edgeElement.data
            let canonicalPrefix = Self.canonicalEdgeIDPrefix(
                source: edge.source,
                target: edge.target,
                label: edge.label,
                edgeType: edge.edgeType
            )
            let sequence = edgeCountByCanonicalPrefix[canonicalPrefix] ?? 0
            edgeCountByCanonicalPrefix[canonicalPrefix] = sequence + 1
            let canonicalID = "\(canonicalPrefix)#\(sequence)"
            let resolvedID = edge.id ?? canonicalID
            let targetNode = nodeByID[edge.target]
            let resolvedStrength = edge.strength ?? Self.inferredStrength(edge, targetNode: targetNode)

            if resolvedID != edge.id || resolvedStrength != edge.strength {
                hasEdgeChanges = true
            }

            return GraphEdgeElement(
                data: GraphEdgeData(
                    id: resolvedID,
                    source: edge.source,
                    target: edge.target,
                    label: edge.label,
                    edgeType: edge.edgeType,
                    edgeColor: edge.edgeColor,
                    tooltip: edge.tooltip,
                    strength: resolvedStrength,
                    isDeactivated: edge.isDeactivated
                )
            )
        }

        let resolvedGraphVersion = customCausalDiagram.graphVersion
            ?? Self.graphVersion(for: customCausalDiagram.graphData)
        let resolvedBaseGraphVersion = customCausalDiagram.baseGraphVersion
            ?? customCausalDiagram.graphVersion
            ?? resolvedGraphVersion
        let hasVersionChanges =
            resolvedGraphVersion != customCausalDiagram.graphVersion
            || resolvedBaseGraphVersion != customCausalDiagram.baseGraphVersion

        guard hasEdgeChanges || hasVersionChanges else {
            return document
        }

        let migratedDiagram = CustomCausalDiagram(
            graphData: CausalGraphData(
                nodes: customCausalDiagram.graphData.nodes,
                edges: migratedEdges
            ),
            lastModified: customCausalDiagram.lastModified ?? Self.timestampNow(),
            graphVersion: resolvedGraphVersion,
            baseGraphVersion: resolvedBaseGraphVersion
        )
        return document.withCustomCausalDiagram(migratedDiagram)
    }

    private func withProgressQuestionSetStateIfMissing(
        _ document: UserDataDocument,
        planningPolicy: PlanningPolicy
    ) -> UserDataDocument {
        guard document.progressQuestionSetState == nil else {
            return document
        }

        let sourceGraphVersion = document.customCausalDiagram?.graphVersion ?? "graph-unknown"
        let fields = document.morningQuestionnaire?.enabledFields ?? [
            .globalSensation,
            .neckTightness,
            .jawSoreness,
            .earFullness,
            .healthAnxiety,
        ]
        var questions = fields.map { field in
            GraphDerivedProgressQuestion(
                id: "morning.\(field.rawValue)",
                title: Self.defaultQuestionTitle(for: field),
                sourceNodeIDs: [],
                sourceEdgeIDs: []
            )
        }
        questions.append(contentsOf: Self.defaultPillarQuestions(
            policy: planningPolicy,
            userDefinedPillars: document.userDefinedPillars
        ))
        let state = ProgressQuestionSetState(
            activeQuestionSetVersion: "question-set.v1",
            activeSourceGraphVersion: sourceGraphVersion,
            activeQuestions: questions,
            declinedGraphVersions: [],
            pendingProposal: nil,
            updatedAt: Self.timestampNow()
        )
        return document.withProgressQuestionSetState(state)
    }

    private func withProgressQuestionSetActiveQuestionsMigrationIfNeeded(
        _ document: UserDataDocument,
        planningPolicy: PlanningPolicy
    ) -> UserDataDocument {
        guard let state = document.progressQuestionSetState else {
            return document
        }

        var activeQuestions = state.activeQuestions
        var pendingProposal = state.pendingProposal
        var didChange = false

        if activeQuestions.isEmpty,
           let pending = pendingProposal,
           pending.proposedQuestionSetVersion == state.activeQuestionSetVersion {
            activeQuestions = pending.questions
            pendingProposal = nil
            didChange = true
        }

        if activeQuestions.isEmpty {
            let morningFields = document.morningQuestionnaire?.enabledFields ?? [
                .globalSensation,
                .neckTightness,
                .jawSoreness,
                .earFullness,
                .healthAnxiety,
                .stressLevel,
                .morningHeadache,
                .dryMouth,
            ]
            var synthesizedQuestions = morningFields.map { field in
                GraphDerivedProgressQuestion(
                    id: "morning.\(field.rawValue)",
                    title: Self.defaultQuestionTitle(for: field),
                    sourceNodeIDs: [],
                    sourceEdgeIDs: []
                )
            }

            synthesizedQuestions.append(contentsOf: Self.defaultPillarQuestions(
                policy: planningPolicy,
                userDefinedPillars: document.userDefinedPillars
            ))

            activeQuestions = Self.deduplicatedQuestions(synthesizedQuestions)
            didChange = true
        }

        guard didChange else {
            return document
        }

        let nextState = ProgressQuestionSetState(
            activeQuestionSetVersion: state.activeQuestionSetVersion,
            activeSourceGraphVersion: state.activeSourceGraphVersion,
            activeQuestions: activeQuestions,
            declinedGraphVersions: state.declinedGraphVersions,
            pendingProposal: pendingProposal,
            updatedAt: Self.timestampNow()
        )
        return document.withProgressQuestionSetState(nextState)
    }

    private func withPlanningStateDefaultsIfMissing(_ document: UserDataDocument) -> UserDataDocument {
        let timestamp = Self.timestampNow()

        let plannerPreferences = document.plannerPreferencesState ?? PlannerPreferencesState(
            defaultAvailableMinutes: PlannerPreferencesState.default.defaultAvailableMinutes,
            modeOverride: nil,
            flareSensitivity: .balanced,
            updatedAt: timestamp,
            dailyTimeBudgetState: DailyTimeBudgetState.from(
                availableMinutes: PlannerPreferencesState.default.defaultAvailableMinutes,
                updatedAt: timestamp
            )
        )
        let plannerState = document.habitPlannerState ?? HabitPlannerState(
            entriesByInterventionID: [:],
            updatedAt: timestamp
        )
        let lensState = document.healthLensState ?? HealthLensState(
            mode: .all,
            pillarSelection: .all,
            updatedAt: timestamp
        )

        if document.plannerPreferencesState != nil,
           document.habitPlannerState != nil,
           document.healthLensState != nil {
            return document
        }

        return document
            .withPlannerPreferencesState(plannerPreferences)
            .withHabitPlannerState(plannerState)
            .withHealthLensState(lensState)
    }

    private func withLegacyAcuteCustomPillarMigrationIfNeeded(
        _ document: UserDataDocument,
        interventionsCatalog: InterventionsCatalog
    ) -> UserDataDocument {
        let acuteInterventions = interventionsCatalog.interventions.filter { definition in
            (definition.planningTags ?? []).contains(.acute)
        }
        if acuteInterventions.isEmpty {
            return document
        }

        let pillarID = "neck"
        let timestamp = Self.timestampNow()
        var userDefinedPillars = document.userDefinedPillars
        if !userDefinedPillars.contains(where: { $0.id == pillarID }) {
            userDefinedPillars.append(
                UserDefinedPillar(
                    id: pillarID,
                    title: "My Neck",
                    templateId: "acute-neck-template",
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    isArchived: false
                )
            )
        }

        let graphNodeIDs = Set(acuteInterventions.compactMap(\.graphNodeId))
        let graphEdgeIDs = Set(acuteInterventions.flatMap { $0.graphEdgeIds ?? [] })
        let interventionIDs = Set(acuteInterventions.map(\.id))
        var pillarAssignments = document.pillarAssignments
        if let assignmentIndex = pillarAssignments.firstIndex(where: { $0.pillarId == pillarID }) {
            let existing = pillarAssignments[assignmentIndex]
            pillarAssignments[assignmentIndex] = PillarAssignment(
                pillarId: pillarID,
                graphNodeIds: Set(existing.graphNodeIds).union(graphNodeIDs).sorted(),
                graphEdgeIds: Set(existing.graphEdgeIds).union(graphEdgeIDs).sorted(),
                interventionIds: Set(existing.interventionIds).union(interventionIDs).sorted(),
                questionId: existing.questionId ?? "pillar.\(pillarID)"
            )
        } else {
            pillarAssignments.append(
                PillarAssignment(
                    pillarId: pillarID,
                    graphNodeIds: graphNodeIDs.sorted(),
                    graphEdgeIds: graphEdgeIDs.sorted(),
                    interventionIds: interventionIDs.sorted(),
                    questionId: "pillar.\(pillarID)"
                )
            )
        }

        let didChange = userDefinedPillars != document.userDefinedPillars
            || pillarAssignments != document.pillarAssignments
        if !didChange {
            return document
        }

        return document
            .withUserDefinedPillars(userDefinedPillars)
            .withPillarAssignments(pillarAssignments)
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
                createdAt: outcome.createdAt,
                graphAssociation: outcome.graphAssociation
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
                createdAt: state.createdAt,
                graphAssociation: state.graphAssociation
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

    private static func canonicalEdgeIDPrefix(
        source: String,
        target: String,
        label: String?,
        edgeType: String?
    ) -> String {
        let normalizedLabel = (label ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedEdgeType = (edgeType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "edge:\(source)|\(target)|\(normalizedEdgeType)|\(normalizedLabel)"
    }

    private static func inferredStrength(_ edge: GraphEdgeData, targetNode: GraphNodeData?) -> Double {
        let normalizedEdgeType = edge.edgeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let baseStrength: Double
        if normalizedEdgeType == "protective" || normalizedEdgeType == "inhibits" {
            baseStrength = -0.6
        } else if normalizedEdgeType == "feedback" {
            baseStrength = 0.7
        } else if normalizedEdgeType == "dashed" {
            baseStrength = 0.45
        } else if normalizedEdgeType == "causal" || normalizedEdgeType == "causes" || normalizedEdgeType == "triggers" || normalizedEdgeType == "forward" {
            baseStrength = 0.8
        } else {
            baseStrength = 0.55
        }

        let evidence = (targetNode?.tooltip?.evidence ?? edge.label ?? edge.tooltip ?? "").lowercased()
        let evidenceFactor: Double
        if evidence.contains("robust") || evidence.contains("strong") || evidence.contains("high") {
            evidenceFactor = 1.0
        } else if evidence.contains("moderate") || evidence.contains("medium") {
            evidenceFactor = 0.75
        } else if evidence.contains("preliminary") || evidence.contains("low") || evidence.contains("limited") {
            evidenceFactor = 0.55
        } else {
            evidenceFactor = 0.4
        }

        let scaled = baseStrength * evidenceFactor
        return min(1.0, max(-1.0, scaled))
    }

    private static func graphVersion(for graphData: CausalGraphData) -> String {
        var fingerprint = graphData.nodes
            .map { node in "\(node.data.id)|\(node.data.styleClass)|\(node.data.confirmed ?? "")|\(node.data.tier ?? -1)" }
            .sorted()
            .joined(separator: ";")
        fingerprint.append("|")
        fingerprint.append(
            graphData.edges
                .map { edge in
                    "\(edge.data.source)|\(edge.data.target)|\(edge.data.edgeType ?? "")|\(edge.data.label ?? "")|\(edge.data.strength ?? 0)"
                }
                .sorted()
                .joined(separator: ";")
        )

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in fingerprint.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "graph-%016llx", hash)
    }

    private static func defaultPillarQuestions(
        policy: PlanningPolicy,
        userDefinedPillars: [UserDefinedPillar]
    ) -> [GraphDerivedProgressQuestion] {
        let corePillars = policy.orderedPillars
        let customPillars = userDefinedPillars
            .filter { !$0.isArchived }
            .sorted { left, right in
                if left.createdAt != right.createdAt {
                    return left.createdAt < right.createdAt
                }
                return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
            }
            .map { pillar in
                HealthPillarDefinition(
                    id: HealthPillar(id: pillar.id),
                    title: pillar.title,
                    rank: 0
                )
            }

        return (corePillars + customPillars).map { pillar in
            GraphDerivedProgressQuestion(
                id: "pillar.\(pillar.id.id)",
                title: "How was your \(pillar.title.lowercased()) today?",
                sourceNodeIDs: [],
                sourceEdgeIDs: []
            )
        }
    }

    private static func deduplicatedQuestions(_ questions: [GraphDerivedProgressQuestion]) -> [GraphDerivedProgressQuestion] {
        var deduped: [GraphDerivedProgressQuestion] = []
        var seenIDs = Set<String>()

        for question in questions {
            if seenIDs.insert(question.id).inserted {
                deduped.append(question)
            }
        }

        return deduped
    }

    private static func defaultQuestionTitle(for field: MorningQuestionField) -> String {
        switch field {
        case .globalSensation:
            return "Global sensation"
        case .neckTightness:
            return "Neck tightness"
        case .jawSoreness:
            return "Jaw soreness"
        case .earFullness:
            return "Ear fullness"
        case .healthAnxiety:
            return "Health anxiety"
        case .stressLevel:
            return "Stress level"
        case .morningHeadache:
            return "Morning headache"
        case .dryMouth:
            return "Dry mouth"
        }
    }
}
