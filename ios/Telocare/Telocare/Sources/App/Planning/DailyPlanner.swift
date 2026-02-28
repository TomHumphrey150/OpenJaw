import Foundation

protocol DailyPlanning {
    func buildProposal(context: DailyPlanningContext) -> DailyPlanProposal
    func recordCompletion(
        interventionID: String,
        plannerState: HabitPlannerState,
        dayKey: String
    ) -> HabitPlannerState
}

struct DailyPlanner: DailyPlanning {
    init() {}

    func buildProposal(context: DailyPlanningContext) -> DailyPlanProposal {
        guard context.availableMinutes > 0 else {
            return DailyPlanProposal(
                mode: context.mode,
                availableMinutes: context.availableMinutes,
                usedMinutes: 0,
                actions: [],
                warnings: ["No available time budget set for today."],
                nextPlannerState: context.plannerState
            )
        }

        let severityByNodeID = Self.symptomSeverityByNodeID(
            morningStates: context.morningStates,
            nightOutcomes: context.nightOutcomes
        )
        let todayAdjustedState = adjustedPlannerStateForNewDay(
            plannerState: context.plannerState,
            inputs: context.inputs,
            todayKey: context.todayKey
        )

        let actionCandidates = context.inputs
            .filter(\.isActive)
            .compactMap { input in
                candidate(
                    input: input,
                    context: context,
                    severityByNodeID: severityByNodeID,
                    plannerState: todayAdjustedState
                )
            }

        let classedCandidates = classifyCandidates(
            actionCandidates,
            mode: context.mode,
            policy: context.policy
        )

        let packed = packCandidates(
            classedCandidates,
            availableMinutes: context.availableMinutes
        )

        var warnings = packed.warnings
        for floorPillar in context.policy.coreFloorPillars {
            let hasFloorAction = packed.actions.contains { action in
                action.pillars.contains(floorPillar)
            }
            if !hasFloorAction {
                warnings.append("\(context.policy.title(for: floorPillar)) floor was not satisfied within the current budget.")
            }
        }

        let nextState = stateByRecordingSuggestions(
            plannerState: todayAdjustedState,
            interventions: packed.actions.map(\.interventionID),
            dayKey: context.todayKey
        )

        return DailyPlanProposal(
            mode: context.mode,
            availableMinutes: context.availableMinutes,
            usedMinutes: packed.usedMinutes,
            actions: packed.actions,
            warnings: warnings,
            nextPlannerState: nextState
        )
    }

    func recordCompletion(
        interventionID: String,
        plannerState: HabitPlannerState,
        dayKey: String
    ) -> HabitPlannerState {
        var nextEntries = plannerState.entriesByInterventionID
        let existing = nextEntries[interventionID] ?? .empty
        let previousDayKey = shiftedDayKey(dayKey, by: -1)
        let previousDayWasCompleted = previousDayKey != nil && existing.lastCompletedDayKey == previousDayKey
        let nextStreak = previousDayWasCompleted ? existing.consecutiveCompletions + 1 : 1
        var nextRung = existing.currentRungIndex
        if nextStreak >= 3 {
            nextRung = max(0, existing.currentRungIndex - 1)
        }

        nextEntries[interventionID] = HabitPlannerEntryState(
            currentRungIndex: nextRung,
            consecutiveCompletions: nextStreak >= 3 ? 0 : nextStreak,
            lastCompletedDayKey: dayKey,
            lastSuggestedDayKey: existing.lastSuggestedDayKey,
            learnedDurationMinutes: existing.learnedDurationMinutes
        )

        return HabitPlannerState(
            entriesByInterventionID: nextEntries,
            updatedAt: DateKeying.timestamp(from: Date())
        )
    }

    private func adjustedPlannerStateForNewDay(
        plannerState: HabitPlannerState,
        inputs: [InputStatus],
        todayKey: String
    ) -> HabitPlannerState {
        let yesterdayKey = shiftedDayKey(todayKey, by: -1)
        let activeIDs = Set(inputs.filter(\.isActive).map(\.id))
        var nextEntries = plannerState.entriesByInterventionID

        for interventionID in activeIDs {
            let entry = nextEntries[interventionID] ?? .empty
            guard entry.lastSuggestedDayKey != todayKey else {
                continue
            }

            var nextRung = entry.currentRungIndex
            if let yesterdayKey, entry.lastSuggestedDayKey == yesterdayKey && entry.lastCompletedDayKey != yesterdayKey {
                nextRung = min(3, nextRung + 1)
            }

            nextEntries[interventionID] = HabitPlannerEntryState(
                currentRungIndex: nextRung,
                consecutiveCompletions: entry.consecutiveCompletions,
                lastCompletedDayKey: entry.lastCompletedDayKey,
                lastSuggestedDayKey: entry.lastSuggestedDayKey,
                learnedDurationMinutes: entry.learnedDurationMinutes
            )
        }

        return HabitPlannerState(
            entriesByInterventionID: nextEntries,
            updatedAt: DateKeying.timestamp(from: Date())
        )
    }

    private func stateByRecordingSuggestions(
        plannerState: HabitPlannerState,
        interventions: [String],
        dayKey: String
    ) -> HabitPlannerState {
        var nextEntries = plannerState.entriesByInterventionID
        for interventionID in interventions {
            let existing = nextEntries[interventionID] ?? .empty
            nextEntries[interventionID] = HabitPlannerEntryState(
                currentRungIndex: existing.currentRungIndex,
                consecutiveCompletions: existing.consecutiveCompletions,
                lastCompletedDayKey: existing.lastCompletedDayKey,
                lastSuggestedDayKey: dayKey,
                learnedDurationMinutes: existing.learnedDurationMinutes
            )
        }
        return HabitPlannerState(
            entriesByInterventionID: nextEntries,
            updatedAt: DateKeying.timestamp(from: Date())
        )
    }

    private func candidate(
        input: InputStatus,
        context: DailyPlanningContext,
        severityByNodeID: [String: Double],
        plannerState: HabitPlannerState
    ) -> PlannedHabitAction? {
        guard let metadata = context.planningMetadataByInterventionID[input.id] else {
            return nil
        }
        guard let ladder = context.ladderByInterventionID[input.id], !ladder.rungs.isEmpty else {
            return nil
        }

        let entry = plannerState.entriesByInterventionID[input.id] ?? .empty
        let rungIndex = min(max(entry.currentRungIndex, 0), ladder.rungs.count - 1)
        let selectedRung = ladder.rungs[rungIndex]
        let estimatedMinutes = Self.estimatedMinutes(
            defaultMinutes: metadata.defaultMinutes,
            rung: selectedRung,
            learnedDurationMinutes: entry.learnedDurationMinutes
        )
        let severity = metadata.acuteTargetNodeIDs
            .map { severityByNodeID[$0] ?? 0 }
            .max() ?? 0
        let topPillarRank = metadata.pillars.map { context.policy.rank(for: $0) }.min() ?? (context.policy.pillarOrder.count + 1)
        let maxRank = max(1, context.policy.pillarOrder.count)
        let pillarWeight = Double((maxRank + 1 - min(topPillarRank, maxRank + 1)) * 100)
        let blockerBoost = metadata.isBlocker ? 60.0 : 0
        let acuteBoost = severity * (context.mode == .flare ? 80.0 : 25.0)
        let streakRecoveryBoost = entry.lastCompletedDayKey == shiftedDayKey(context.todayKey, by: -1) ? 0.0 : 15.0
        let evidenceWeight = Double(evidenceRank(for: input.evidenceLevel) * 6)
        let preferredWindowPenalty = Self.preferredWindowPenalty(
            preferredWindows: metadata.preferredWindows,
            selectedSlotStartMinutes: context.selectedSlotStartMinutes
        )
        let priorityScore = pillarWeight + blockerBoost + acuteBoost + streakRecoveryBoost + evidenceWeight - preferredWindowPenalty

        return PlannedHabitAction(
            interventionID: input.id,
            title: input.name,
            pillars: metadata.pillars,
            tags: metadata.tags,
            selectedRung: selectedRung,
            estimatedMinutes: estimatedMinutes,
            priorityClass: 3,
            priorityScore: priorityScore,
            rationale: rationaleText(
                mode: context.mode,
                metadata: metadata,
                severity: severity,
                preferredWindowPenalty: preferredWindowPenalty
            )
        )
    }

    private func classifyCandidates(
        _ candidates: [PlannedHabitAction],
        mode: PlanningMode,
        policy: PlanningPolicy
    ) -> [PlannedHabitAction] {
        let highPriorityPillarCutoff = max(1, min(policy.highPriorityPillarCutoff, max(1, policy.pillarOrder.count)))
        return candidates.map { candidate in
            let priorityClass: Int
            if candidate.tags.contains(.coreFloor)
                && candidate.pillars.contains(where: { policy.coreFloorPillars.contains($0) })
            {
                priorityClass = 0
            } else if candidate.tags.contains(.blocker), candidate.pillars.contains(where: { policy.rank(for: $0) <= highPriorityPillarCutoff }) {
                priorityClass = 1
            } else if mode == .flare && candidate.tags.contains(.acute) {
                priorityClass = 2
            } else if mode == .baseline && candidate.tags.contains(.foundation) {
                priorityClass = 2
            } else {
                priorityClass = 3
            }

            return PlannedHabitAction(
                interventionID: candidate.interventionID,
                title: candidate.title,
                pillars: candidate.pillars,
                tags: candidate.tags,
                selectedRung: candidate.selectedRung,
                estimatedMinutes: candidate.estimatedMinutes,
                priorityClass: priorityClass,
                priorityScore: candidate.priorityScore,
                rationale: candidate.rationale
            )
        }
    }

    private func packCandidates(
        _ candidates: [PlannedHabitAction],
        availableMinutes: Int
    ) -> (actions: [PlannedHabitAction], usedMinutes: Int, warnings: [String]) {
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.priorityClass != rhs.priorityClass {
                return lhs.priorityClass < rhs.priorityClass
            }
            if lhs.priorityScore != rhs.priorityScore {
                return lhs.priorityScore > rhs.priorityScore
            }
            let lhsEfficiency = lhs.priorityScore / Double(max(1, lhs.estimatedMinutes))
            let rhsEfficiency = rhs.priorityScore / Double(max(1, rhs.estimatedMinutes))
            if lhsEfficiency != rhsEfficiency {
                return lhsEfficiency > rhsEfficiency
            }
            return lhs.interventionID < rhs.interventionID
        }

        var usedMinutes = 0
        var selected: [PlannedHabitAction] = []
        var warnings: [String] = []
        for candidate in ordered {
            if usedMinutes + candidate.estimatedMinutes > availableMinutes {
                continue
            }
            selected.append(candidate)
            usedMinutes += candidate.estimatedMinutes
        }

        if selected.isEmpty {
            warnings.append("No habits fit the current time budget.")
        }

        if availableMinutes - usedMinutes < 5 {
            return (selected, usedMinutes, warnings)
        }

        let remaining = availableMinutes - usedMinutes
        if remaining > 0, selected.isEmpty == false {
            warnings.append("Unused time budget: \(remaining) min.")
        }

        return (selected, usedMinutes, warnings)
    }

    private func rationaleText(
        mode: PlanningMode,
        metadata: HabitPlanningMetadata,
        severity: Double,
        preferredWindowPenalty: Double
    ) -> String {
        let modeText = mode == .flare ? "flare mode" : "baseline mode"
        let severityPercent = Int((severity * 100).rounded())
        if preferredWindowPenalty > 0 {
            return "\(modeText), \(metadata.foundationRole.rawValue), severity \(severityPercent)%, outside preferred window."
        }
        return "\(modeText), \(metadata.foundationRole.rawValue), severity \(severityPercent)%."
    }

    private static func estimatedMinutes(
        defaultMinutes: Int,
        rung: HabitLadderRung,
        learnedDurationMinutes: Double?
    ) -> Int {
        let learned = Int((learnedDurationMinutes ?? Double(defaultMinutes)).rounded())
        let scaled = Int((Double(learned) * rung.durationMultiplier).rounded())
        return max(rung.minimumMinutes, scaled)
    }

    private static func symptomSeverityByNodeID(
        morningStates: [MorningState],
        nightOutcomes: [NightOutcome]
    ) -> [String: Double] {
        guard let latestMorning = morningStates.sorted(by: { $0.nightId > $1.nightId }).first else {
            return [:]
        }

        var map: [String: Double] = [:]
        map["MICRO"] = normalized10(latestMorning.globalSensation)
        map["NECK_TIGHTNESS"] = normalized10(latestMorning.neckTightness)
        map["TMD"] = normalized10(latestMorning.jawSoreness)
        map["EAR"] = normalized10(latestMorning.earFullness)
        map["HEALTH_ANXIETY"] = normalized10(latestMorning.healthAnxiety)
        map["STRESS"] = normalized10(latestMorning.stressLevel)
        map["HEADACHES"] = normalized10(latestMorning.morningHeadache)
        map["SALIVA"] = normalized10(latestMorning.dryMouth)

        if let latestNight = nightOutcomes.sorted(by: { $0.nightId > $1.nightId }).first {
            let microRate = latestNight.microArousalRatePerHour ?? 0
            let normalized = min(1.0, max(0.0, microRate / 20.0))
            map["MICRO"] = max(map["MICRO"] ?? 0, normalized)
        }

        return map
    }

    private static func normalized10(_ value: Double?) -> Double {
        guard let value else {
            return 0
        }
        return min(1.0, max(0.0, value / 10.0))
    }

    private static func preferredWindowPenalty(
        preferredWindows: [PreferredTimeWindow],
        selectedSlotStartMinutes: [Int]
    ) -> Double {
        guard !preferredWindows.isEmpty else {
            return 0
        }
        guard !selectedSlotStartMinutes.isEmpty else {
            return 24
        }

        for slot in selectedSlotStartMinutes {
            if preferredWindows.contains(where: { $0.contains(startMinute: slot) }) {
                return 0
            }
        }

        return 24
    }

    private func evidenceRank(for evidenceLevel: String?) -> Int {
        guard let normalized = evidenceLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return 0
        }
        if normalized.contains("robust") || normalized.contains("strong") || normalized.contains("high") {
            return 5
        }
        if normalized.contains("moderate") || normalized.contains("medium") {
            return 3
        }
        if normalized.contains("preliminary") || normalized.contains("emerging") || normalized.contains("low") {
            return 1
        }
        return 0
    }

    private func shiftedDayKey(_ dayKey: String, by offset: Int) -> String? {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        guard
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = Calendar(identifier: .gregorian)
        guard let date = components.date else {
            return nil
        }
        guard let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date) else {
            return nil
        }
        let shiftedComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: shifted)
        guard
            let shiftedYear = shiftedComponents.year,
            let shiftedMonth = shiftedComponents.month,
            let shiftedDay = shiftedComponents.day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", shiftedYear, shiftedMonth, shiftedDay)
    }
}

protocol FlareDetection {
    func detectSuggestion(
        mode: PlanningMode,
        morningStates: [MorningState],
        nightOutcomes: [NightOutcome],
        sensitivity: FlareSensitivity
    ) -> FlareSuggestion?
}

struct FlareDetectionService: FlareDetection {
    private let policy: PlanningPolicy

    init(policy: PlanningPolicy = .default) {
        self.policy = policy
    }

    func detectSuggestion(
        mode: PlanningMode,
        morningStates: [MorningState],
        nightOutcomes: [NightOutcome],
        sensitivity: FlareSensitivity
    ) -> FlareSuggestion? {
        let snapshots = buildSnapshots(morningStates: morningStates, nightOutcomes: nightOutcomes)
        let lookback = max(
            3,
            policy.flareLookbackDays,
            policy.flareEnterRequiredDays,
            policy.flareExitStableDays
        )
        guard snapshots.count >= lookback else {
            return nil
        }

        let recent = Array(snapshots.prefix(lookback))
        let rollingBaseline = snapshots.map(\.normalizedSymptomIndex).reduce(0, +) / Double(snapshots.count)
        let enterThreshold: Double
        let exitThreshold: Double
        switch sensitivity {
        case .balanced:
            enterThreshold = policy.flareEnterThreshold
            exitThreshold = policy.flareExitThreshold
        case .earlyWarning:
            enterThreshold = max(0.05, policy.flareEnterThreshold - 0.10)
            exitThreshold = max(0.05, policy.flareExitThreshold - 0.05)
        case .highConfidence:
            enterThreshold = min(0.95, policy.flareEnterThreshold + 0.10)
            exitThreshold = min(0.95, policy.flareExitThreshold + 0.05)
        }

        let worsenCount = recent.filter { $0.normalizedSymptomIndex >= enterThreshold }.count
        let stabilizeCount = recent.filter { $0.normalizedSymptomIndex < exitThreshold }.count
        let latest = recent[0]

        if mode == .baseline {
            if worsenCount >= policy.flareEnterRequiredDays, latest.normalizedSymptomIndex > rollingBaseline {
                return FlareSuggestion(
                    direction: .enterFlare,
                    reason: "\(policy.flareEnterRequiredDays) of last \(lookback) mornings worsened above threshold.",
                    snapshots: recent
                )
            }
            return nil
        }

        if stabilizeCount >= policy.flareExitStableDays {
            return FlareSuggestion(
                direction: .exitFlare,
                reason: "\(policy.flareExitStableDays) stable mornings are below recovery threshold.",
                snapshots: recent
            )
        }
        return nil
    }

    private func buildSnapshots(
        morningStates: [MorningState],
        nightOutcomes: [NightOutcome]
    ) -> [FlareDetectionSnapshot] {
        let sortedMorning = morningStates.sorted { $0.nightId > $1.nightId }
        let nightByID = Dictionary(uniqueKeysWithValues: nightOutcomes.map { ($0.nightId, $0) })
        guard !sortedMorning.isEmpty else {
            return []
        }

        return sortedMorning.map { state in
            let metrics = [
                normalized10(state.globalSensation),
                normalized10(state.neckTightness),
                normalized10(state.jawSoreness),
                normalized10(state.earFullness),
                normalized10(state.healthAnxiety),
                normalized10(state.stressLevel),
                normalized10(state.morningHeadache),
                normalized10(state.dryMouth),
                normalizedNight(nightByID[state.nightId]?.microArousalRatePerHour),
            ]
            let average = metrics.reduce(0, +) / Double(metrics.count)
            return FlareDetectionSnapshot(
                dayKey: state.nightId,
                normalizedSymptomIndex: average,
                rollingBaseline: average
            )
        }
    }

    private func normalized10(_ value: Double?) -> Double {
        guard let value else {
            return 0
        }
        return min(1.0, max(0.0, value / 10.0))
    }

    private func normalizedNight(_ value: Double?) -> Double {
        guard let value else {
            return 0
        }
        return min(1.0, max(0.0, value / 20.0))
    }
}
