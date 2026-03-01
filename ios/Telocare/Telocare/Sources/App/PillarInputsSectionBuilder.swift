import Foundation

struct PillarInputsSection: Identifiable, Equatable {
    let pillar: HealthPillar
    let title: String
    let inputs: [InputStatus]

    var id: String {
        pillar.id
    }
}

struct PillarInputsSectionBuilder {
    func build(
        inputs: [InputStatus],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        pillarAssignments: [PillarAssignment],
        orderedPillars: [HealthPillarDefinition]
    ) -> [PillarInputsSection] {
        let rankByPillarID = Dictionary(
            uniqueKeysWithValues: orderedPillars.enumerated().map { index, definition in
                (definition.id.id, index)
            }
        )
        let titleByPillarID = Dictionary(
            uniqueKeysWithValues: orderedPillars.map { definition in
                (definition.id.id, definition.title)
            }
        )
        let pillarIDsByInterventionID = resolvePillarIDsByInterventionID(
            assignments: pillarAssignments,
            planningMetadataByInterventionID: planningMetadataByInterventionID
        )

        var sectionBuckets: [String: [InputStatus]] = [:]
        for input in inputs {
            let pillar = primaryPillar(
                for: input,
                pillarIDsByInterventionID: pillarIDsByInterventionID,
                rankByPillarID: rankByPillarID
            )
            sectionBuckets[pillar.id, default: []].append(input)
        }

        let orderedPillarIDs = sectionBuckets.keys.sorted { left, right in
            let leftRank = rankByPillarID[left] ?? Int.max
            let rightRank = rankByPillarID[right] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }

        return orderedPillarIDs.compactMap { pillarID in
            guard let sectionInputs = sectionBuckets[pillarID], !sectionInputs.isEmpty else {
                return nil
            }

            let title = titleByPillarID[pillarID] ?? HealthPillar(id: pillarID).displayName
            return PillarInputsSection(
                pillar: HealthPillar(id: pillarID),
                title: title,
                inputs: sectionInputs
            )
        }
    }

    private func primaryPillar(
        for input: InputStatus,
        pillarIDsByInterventionID: [String: Set<String>],
        rankByPillarID: [String: Int]
    ) -> HealthPillar {
        guard let pillarIDs = pillarIDsByInterventionID[input.id], !pillarIDs.isEmpty else {
            return HealthPillar(id: "general")
        }

        let sorted = pillarIDs.sorted { left, right in
            let leftRank = rankByPillarID[left] ?? Int.max
            let rightRank = rankByPillarID[right] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
        return HealthPillar(id: sorted.first ?? "general")
    }

    private func resolvePillarIDsByInterventionID(
        assignments: [PillarAssignment],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata]
    ) -> [String: Set<String>] {
        var pillarIDsByInterventionID: [String: Set<String>] = [:]

        for (interventionID, metadata) in planningMetadataByInterventionID {
            let ids = Set(metadata.pillars.map(\.id))
            if !ids.isEmpty {
                pillarIDsByInterventionID[interventionID, default: []].formUnion(ids)
            }
        }

        for assignment in assignments {
            let pillarID = assignment.pillarId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pillarID.isEmpty else {
                continue
            }

            for interventionID in assignment.interventionIds {
                pillarIDsByInterventionID[interventionID, default: []].insert(pillarID)
            }
        }

        return pillarIDsByInterventionID
    }
}
