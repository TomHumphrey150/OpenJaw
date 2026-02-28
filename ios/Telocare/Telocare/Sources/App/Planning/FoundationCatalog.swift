import Foundation

struct FoundationCatalog: Codable, Equatable, Sendable {
    let schemaVersion: String
    let sourceReportPath: String
    let generatedAt: String
    let pillars: [FoundationCatalogPillar]
    let interventionMappings: [FoundationCatalogInterventionMapping]
}

struct FoundationCatalogPillar: Codable, Equatable, Sendable {
    let id: HealthPillar
    let rank: Int
    let title: String
    let subdomains: [String]
    let baselineMaintenances: [String]
    let blockerPatterns: [String]
}

struct FoundationCatalogInterventionMapping: Codable, Equatable, Sendable {
    let interventionID: String
    let pillars: [HealthPillar]
    let tags: [HabitPlanningTag]
    let foundationRole: FoundationRole
    let acuteTargetNodeIDs: [String]
    let defaultMinutes: Int
    let ladderTemplateID: String
    let preferredWindows: [PreferredTimeWindow]?
}

struct HabitPlanningMetadataResolver {
    private let foundationCatalogByInterventionID: [String: HabitPlanningMetadata]
    private let interventionsCatalogByInterventionID: [String: HabitPlanningMetadata]
    private let planningPolicy: PlanningPolicy

    init(
        foundationCatalog: FoundationCatalog? = nil,
        interventionsCatalog: InterventionsCatalog = .empty,
        planningPolicy: PlanningPolicy = .default
    ) {
        foundationCatalogByInterventionID = Dictionary(
            uniqueKeysWithValues: (foundationCatalog?.interventionMappings ?? []).map { mapping in
                (
                    mapping.interventionID,
                    HabitPlanningMetadata(
                        interventionID: mapping.interventionID,
                        pillars: mapping.pillars,
                        tags: mapping.tags,
                        acuteTargetNodeIDs: mapping.acuteTargetNodeIDs,
                        foundationRole: mapping.foundationRole,
                        defaultMinutes: max(1, mapping.defaultMinutes),
                        ladderTemplateID: mapping.ladderTemplateID,
                        preferredWindows: mapping.preferredWindows ?? []
                    )
                )
            }
        )
        interventionsCatalogByInterventionID = Dictionary(
            uniqueKeysWithValues: interventionsCatalog.interventions.compactMap { definition in
                guard let metadata = Self.metadata(from: definition) else {
                    return nil
                }
                return (definition.id, metadata)
            }
        )
        self.planningPolicy = planningPolicy
    }

    func metadataByInterventionID(
        for inputs: [InputStatus]
    ) -> [String: HabitPlanningMetadata] {
        inputs.reduce(into: [:]) { partialResult, input in
            if let mapped = foundationCatalogByInterventionID[input.id] {
                partialResult[input.id] = mapped
                return
            }
            if let mapped = interventionsCatalogByInterventionID[input.id] {
                partialResult[input.id] = mapped
                return
            }
            partialResult[input.id] = genericMetadata(for: input)
        }
    }

    func ladderByInterventionID(
        metadataByInterventionID: [String: HabitPlanningMetadata]
    ) -> [String: HabitLadderDefinition] {
        metadataByInterventionID.reduce(into: [:]) { partialResult, entry in
            let metadata = entry.value
            partialResult[entry.key] = HabitLadderDefinition(
                interventionID: metadata.interventionID,
                rungs: ladderTemplate(for: metadata)
            )
        }
    }

    private func ladderTemplate(for metadata: HabitPlanningMetadata) -> [HabitLadderRung] {
        let base = max(planningPolicy.ladder.minimumMinutes, metadata.defaultMinutes)
        let full = max(planningPolicy.ladder.minimumMinutes, Int((Double(base) * planningPolicy.ladder.fullMultiplier).rounded()))
        let reduced = max(planningPolicy.ladder.minimumMinutes, Int((Double(base) * planningPolicy.ladder.reducedMultiplier).rounded()))
        let minimal = max(planningPolicy.ladder.minimumMinutes, Int((Double(base) * planningPolicy.ladder.minimalMultiplier).rounded()))
        let micro = max(planningPolicy.ladder.minimumMinutes, Int((Double(base) * planningPolicy.ladder.microMultiplier).rounded()))

        return [
            HabitLadderRung(id: "full", title: "Full", durationMultiplier: planningPolicy.ladder.fullMultiplier, minimumMinutes: full),
            HabitLadderRung(id: "reduced", title: "Reduced", durationMultiplier: planningPolicy.ladder.reducedMultiplier, minimumMinutes: reduced),
            HabitLadderRung(id: "minimal", title: "Minimal", durationMultiplier: planningPolicy.ladder.minimalMultiplier, minimumMinutes: minimal),
            HabitLadderRung(id: "micro", title: "Micro", durationMultiplier: planningPolicy.ladder.microMultiplier, minimumMinutes: micro),
        ]
    }

    private static func metadata(from definition: InterventionDefinition) -> HabitPlanningMetadata? {
        guard let pillars = definition.pillars, !pillars.isEmpty else {
            return nil
        }
        let tags = definition.planningTags ?? [.foundation, .maintenance]
        let foundationRole = definition.foundationRole ?? (tags.contains(.blocker) ? .blocker : .maintenance)

        return HabitPlanningMetadata(
            interventionID: definition.id,
            pillars: pillars,
            tags: tags,
            acuteTargetNodeIDs: definition.acuteTargets ?? definition.graphNodeId.map { [$0] } ?? [],
            foundationRole: foundationRole,
            defaultMinutes: max(1, definition.defaultMinutes ?? 15),
            ladderTemplateID: definition.ladderTemplateID ?? "general",
            preferredWindows: definition.preferredWindows ?? Self.preferredWindows(from: definition.timeOfDay)
        )
    }

    private func genericMetadata(for input: InputStatus) -> HabitPlanningMetadata {
        let fallbackPillar = planningPolicy.pillarOrder.first ?? HealthPillar(id: "general")
        return HabitPlanningMetadata(
            interventionID: input.id,
            pillars: [fallbackPillar],
            tags: [.foundation, .maintenance],
            acuteTargetNodeIDs: input.graphNodeID.map { [$0] } ?? [],
            foundationRole: .maintenance,
            defaultMinutes: defaultMinutes(for: input),
            ladderTemplateID: "general",
            preferredWindows: Self.preferredWindows(from: input.timeOfDay)
        )
    }

    private func defaultMinutes(for input: InputStatus) -> Int {
        if let doseState = input.doseState {
            return max(planningPolicy.ladder.minimumMinutes, Int(doseState.goal.rounded()))
        }
        switch input.trackingMode {
        case .dose:
            return 20
        case .binary:
            return 15
        }
    }

    private static func preferredWindows(from timeOfDay: [InterventionTimeOfDay]?) -> [PreferredTimeWindow] {
        guard let timeOfDay, !timeOfDay.isEmpty else {
            return []
        }

        let unique = Set(timeOfDay)
        if unique.contains(.anytime) {
            return []
        }

        var windows: [PreferredTimeWindow] = []
        if unique.contains(.morning) {
            windows.append(PreferredTimeWindow(startMinutes: 5 * 60, endMinutes: 12 * 60))
        }
        if unique.contains(.afternoon) {
            windows.append(PreferredTimeWindow(startMinutes: 12 * 60, endMinutes: 17 * 60))
        }
        if unique.contains(.evening) {
            windows.append(PreferredTimeWindow(startMinutes: 17 * 60, endMinutes: 21 * 60))
        }
        if unique.contains(.preBed) {
            windows.append(PreferredTimeWindow(startMinutes: 21 * 60, endMinutes: 24 * 60))
        }

        return windows
    }
}
