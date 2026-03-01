import Foundation

struct KitchenGardenSnapshot: Equatable, Identifiable {
    let pillar: HealthPillarDefinition
    let mappedHabitCount: Int
    let activeHabitCount: Int
    let completedHabitCount: Int
    let effortFraction: Double
    let effortStage: Int

    var id: String {
        pillar.id.id
    }
}

struct HarvestTableSnapshot: Equatable, Identifiable {
    let pillar: HealthPillarDefinition
    let effortFraction: Double
    let effortStage: Int
    let rollingOutcomeFraction: Double?
    let foodStage: Int
    let outcomeSampleCount: Int

    var id: String {
        pillar.id.id
    }
}

struct PillarVisualSnapshotBuilder {
    private static let rollingWindowDays = 7
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func buildKitchenGarden(
        pillars: [HealthPillarDefinition],
        inputs: [InputStatus],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        pillarAssignments: [PillarAssignment]
    ) -> [KitchenGardenSnapshot] {
        let effortByPillarID = effortByPillar(
            pillars: pillars,
            inputs: inputs,
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            pillarAssignments: pillarAssignments
        )

        return pillars.map { pillar in
            let effort = effortByPillarID[pillar.id.id] ?? .empty
            return KitchenGardenSnapshot(
                pillar: pillar,
                mappedHabitCount: effort.mappedHabitCount,
                activeHabitCount: effort.activeHabitCount,
                completedHabitCount: effort.completedHabitCount,
                effortFraction: effort.fraction,
                effortStage: stage(for: effort.fraction)
            )
        }
    }

    func buildHarvestTable(
        pillars: [HealthPillarDefinition],
        inputs: [InputStatus],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        pillarAssignments: [PillarAssignment],
        pillarCheckIns: [PillarCheckIn]
    ) -> [HarvestTableSnapshot] {
        let effortByPillarID = effortByPillar(
            pillars: pillars,
            inputs: inputs,
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            pillarAssignments: pillarAssignments
        )
        let outcomeByPillarID = rollingOutcomeByPillar(
            pillars: pillars,
            pillarCheckIns: pillarCheckIns
        )

        return pillars.map { pillar in
            let effort = effortByPillarID[pillar.id.id] ?? .empty
            let outcome = outcomeByPillarID[pillar.id.id]
            let outcomeFraction = outcome?.fraction
            return HarvestTableSnapshot(
                pillar: pillar,
                effortFraction: effort.fraction,
                effortStage: stage(for: effort.fraction),
                rollingOutcomeFraction: outcomeFraction,
                foodStage: stage(for: outcomeFraction ?? 0),
                outcomeSampleCount: outcome?.sampleCount ?? 0
            )
        }
    }

    private func effortByPillar(
        pillars: [HealthPillarDefinition],
        inputs: [InputStatus],
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        pillarAssignments: [PillarAssignment]
    ) -> [String: PillarEffort] {
        var accumulatorsByPillarID = Dictionary(
            uniqueKeysWithValues: pillars.map { ($0.id.id, PillarEffort.empty) }
        )
        let mappedPillarIDsByInterventionID = resolvePillarIDsByInterventionID(
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            pillarAssignments: pillarAssignments
        )

        for input in inputs {
            guard let mappedPillarIDs = mappedPillarIDsByInterventionID[input.id], !mappedPillarIDs.isEmpty else {
                continue
            }

            for pillarID in mappedPillarIDs {
                guard var accumulator = accumulatorsByPillarID[pillarID] else {
                    continue
                }
                accumulator.mappedHabitCount += 1
                if input.isActive {
                    accumulator.activeHabitCount += 1
                    if input.isCheckedToday {
                        accumulator.completedHabitCount += 1
                    }
                }
                accumulatorsByPillarID[pillarID] = accumulator
            }
        }

        return accumulatorsByPillarID.mapValues { accumulator in
            PillarEffort(
                mappedHabitCount: accumulator.mappedHabitCount,
                activeHabitCount: accumulator.activeHabitCount,
                completedHabitCount: accumulator.completedHabitCount,
                fraction: ratio(completed: accumulator.completedHabitCount, total: accumulator.activeHabitCount)
            )
        }
    }

    private func rollingOutcomeByPillar(
        pillars: [HealthPillarDefinition],
        pillarCheckIns: [PillarCheckIn]
    ) -> [String: PillarOutcome] {
        let datedCheckIns = pillarCheckIns
            .compactMap { checkIn -> DatedPillarCheckIn? in
                guard let date = dayDate(from: checkIn.nightId) else {
                    return nil
                }
                return DatedPillarCheckIn(date: date, responsesByPillarID: checkIn.responsesByPillarId)
            }
            .sorted { left, right in
                left.date > right.date
            }

        guard let latestDate = datedCheckIns.first?.date else {
            return [:]
        }
        guard let lowerBound = calendar.date(byAdding: .day, value: -(Self.rollingWindowDays - 1), to: latestDate) else {
            return [:]
        }

        let inWindow = datedCheckIns.filter { checkIn in
            checkIn.date >= lowerBound && checkIn.date <= latestDate
        }

        var outcomeByPillarID: [String: PillarOutcome] = [:]

        for pillar in pillars {
            let responses = inWindow.compactMap { checkIn in
                checkIn.responsesByPillarID[pillar.id.id]
            }
            guard !responses.isEmpty else {
                continue
            }

            let total = responses.reduce(0) { partial, value in
                partial + value
            }
            let average = Double(total) / Double(responses.count)
            outcomeByPillarID[pillar.id.id] = PillarOutcome(
                fraction: normalizedOutcomeFraction(for: average),
                sampleCount: responses.count
            )
        }

        return outcomeByPillarID
    }

    private func normalizedOutcomeFraction(for rawValue: Double) -> Double {
        let minimum = Double(FoundationCheckInScale.minimumValue)
        let maximum = Double(FoundationCheckInScale.maximumValue)
        guard maximum > minimum else {
            return 0
        }

        return clamped((rawValue - minimum) / (maximum - minimum))
    }

    private func ratio(completed: Int, total: Int) -> Double {
        guard total > 0 else {
            return 0
        }

        return clamped(Double(completed) / Double(total))
    }

    private func stage(for fraction: Double) -> Int {
        let value = clamped(fraction)
        if value >= 1 {
            return 10
        }

        return min(10, max(1, Int(value * 10) + 1))
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func dayDate(from dayID: String) -> Date? {
        Self.dayFormatter.date(from: dayID)
    }

    private func resolvePillarIDsByInterventionID(
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        pillarAssignments: [PillarAssignment]
    ) -> [String: Set<String>] {
        var pillarIDsByInterventionID: [String: Set<String>] = [:]

        for (interventionID, metadata) in planningMetadataByInterventionID {
            let pillarIDs = Set(metadata.pillars.map(\.id))
            if pillarIDs.isEmpty {
                continue
            }
            pillarIDsByInterventionID[interventionID, default: []].formUnion(pillarIDs)
        }

        for assignment in pillarAssignments {
            let pillarID = assignment.pillarId.trimmingCharacters(in: .whitespacesAndNewlines)
            if pillarID.isEmpty {
                continue
            }

            for interventionID in assignment.interventionIds {
                pillarIDsByInterventionID[interventionID, default: []].insert(pillarID)
            }
        }

        return pillarIDsByInterventionID
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct PillarEffort {
    var mappedHabitCount: Int
    var activeHabitCount: Int
    var completedHabitCount: Int
    var fraction: Double

    static let empty = PillarEffort(
        mappedHabitCount: 0,
        activeHabitCount: 0,
        completedHabitCount: 0,
        fraction: 0
    )
}

private struct PillarOutcome {
    let fraction: Double
    let sampleCount: Int
}

private struct DatedPillarCheckIn {
    let date: Date
    let responsesByPillarID: [String: Int]
}
