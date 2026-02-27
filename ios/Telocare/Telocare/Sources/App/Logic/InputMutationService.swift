import Foundation

protocol InputMutationService {
    func toggleCheckIn(
        inputID: String,
        context: InputMutationContext
    ) -> InputMutationResult?

    func mutateDose(
        inputID: String,
        operation: InputDoseMutationOperation,
        context: InputMutationContext
    ) -> InputMutationResult?

    func updateDoseSettings(
        inputID: String,
        dailyGoal: Double,
        increment: Double,
        context: InputMutationContext
    ) -> InputMutationResult?

    func toggleActive(
        inputID: String,
        context: InputMutationContext
    ) -> InputMutationResult?
}

struct InputMutationContext {
    let snapshot: DashboardSnapshot
    let dailyCheckIns: [String: [String]]
    let dailyDoseProgress: [String: [String: Double]]
    let interventionCompletionEvents: [InterventionCompletionEvent]
    let interventionDoseSettings: [String: DoseSettings]
    let activeInterventions: [String]
    let now: Date
    let maxCompletionEventsPerIntervention: Int
}

struct InputMutationResult {
    let snapshot: DashboardSnapshot
    let dailyCheckIns: [String: [String]]
    let dailyDoseProgress: [String: [String: Double]]
    let interventionCompletionEvents: [InterventionCompletionEvent]
    let interventionDoseSettings: [String: DoseSettings]
    let activeInterventions: [String]
    let patch: UserDataPatch
    let successMessage: String
    let failureMessage: String
}

enum InputDoseMutationOperation {
    case increment
    case decrement
    case reset
}

struct DefaultInputMutationService: InputMutationService {
    func toggleCheckIn(
        inputID: String,
        context: InputMutationContext
    ) -> InputMutationResult? {
        guard let index = context.snapshot.inputs.firstIndex(where: { $0.id == inputID }) else {
            return nil
        }

        let currentInput = context.snapshot.inputs[index]
        guard currentInput.trackingMode == .binary else {
            return nil
        }

        let currentDayCount = dayCount(for: currentInput)
        let nextCheckedToday = !currentInput.isCheckedToday
        let nextDayCount = updatedDayCount(
            currentDayCount: currentDayCount,
            currentlyCheckedToday: currentInput.isCheckedToday
        )
        let nextStatusText = statusText(
            dayCount: nextDayCount,
            checkedToday: nextCheckedToday
        )

        let eventTimestamp = DateKeying.timestamp(from: context.now)
        let nextInterventionCompletionEvents: [InterventionCompletionEvent]
        if nextCheckedToday {
            nextInterventionCompletionEvents = appendCompletionEvent(
                InterventionCompletionEvent(
                    interventionId: currentInput.id,
                    occurredAt: eventTimestamp,
                    source: .binaryCheck
                ),
                to: context.interventionCompletionEvents,
                maxPerIntervention: context.maxCompletionEventsPerIntervention
            )
        } else {
            nextInterventionCompletionEvents = context.interventionCompletionEvents
        }

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .binary,
            statusText: nextStatusText,
            completion: Double(nextDayCount) / 7.0,
            isCheckedToday: nextCheckedToday,
            doseState: nil,
            completionEvents: completionEvents(
                for: currentInput.id,
                in: nextInterventionCompletionEvents
            ),
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState,
            timeOfDay: currentInput.timeOfDay
        )

        let dateKey = DateKeying.localDateKey(from: context.now)
        let nextDailyCheckIns = updatedDailyCheckIns(
            from: context.dailyCheckIns,
            dateKey: dateKey,
            interventionID: currentInput.id,
            isChecked: nextCheckedToday
        )
        let nextSnapshot = replacingInput(
            in: context.snapshot,
            at: index,
            with: nextInput
        )

        let successMessage = nextCheckedToday
            ? "\(currentInput.name) checked for today."
            : "\(currentInput.name) unchecked for today."
        let failureMessage = "Could not save \(currentInput.name) check-in. Reverted."

        return InputMutationResult(
            snapshot: nextSnapshot,
            dailyCheckIns: nextDailyCheckIns,
            dailyDoseProgress: context.dailyDoseProgress,
            interventionCompletionEvents: nextInterventionCompletionEvents,
            interventionDoseSettings: context.interventionDoseSettings,
            activeInterventions: context.activeInterventions,
            patch: .dailyCheckInsAndCompletionEvents(
                nextDailyCheckIns,
                nextInterventionCompletionEvents
            ),
            successMessage: successMessage,
            failureMessage: failureMessage
        )
    }

    func mutateDose(
        inputID: String,
        operation: InputDoseMutationOperation,
        context: InputMutationContext
    ) -> InputMutationResult? {
        guard let index = context.snapshot.inputs.firstIndex(where: { $0.id == inputID }) else {
            return nil
        }

        let currentInput = context.snapshot.inputs[index]
        guard currentInput.trackingMode == .dose else {
            return nil
        }
        guard let currentDoseState = currentInput.doseState else {
            return nil
        }

        let nextManualValue: Double
        switch operation {
        case .increment:
            nextManualValue = currentDoseState.manualValue + currentDoseState.increment
        case .decrement:
            nextManualValue = max(0, currentDoseState.manualValue - currentDoseState.increment)
        case .reset:
            nextManualValue = 0
        }

        let nextDoseState = InputDoseState(
            manualValue: nextManualValue,
            healthValue: currentDoseState.healthValue,
            goal: currentDoseState.goal,
            increment: currentDoseState.increment,
            unit: currentDoseState.unit
        )

        let eventTimestamp = DateKeying.timestamp(from: context.now)
        let nextInterventionCompletionEvents: [InterventionCompletionEvent]
        if operation == .increment {
            nextInterventionCompletionEvents = appendCompletionEvent(
                InterventionCompletionEvent(
                    interventionId: currentInput.id,
                    occurredAt: eventTimestamp,
                    source: .doseIncrement
                ),
                to: context.interventionCompletionEvents,
                maxPerIntervention: context.maxCompletionEventsPerIntervention
            )
        } else {
            nextInterventionCompletionEvents = context.interventionCompletionEvents
        }

        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .dose,
            statusText: doseStatusText(for: nextDoseState),
            completion: nextDoseState.completionClamped,
            isCheckedToday: nextDoseState.isGoalMet,
            doseState: nextDoseState,
            completionEvents: completionEvents(
                for: currentInput.id,
                in: nextInterventionCompletionEvents
            ),
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState,
            timeOfDay: currentInput.timeOfDay
        )

        let dateKey = DateKeying.localDateKey(from: context.now)
        let nextDailyDoseProgress = updatedDailyDoseProgress(
            from: context.dailyDoseProgress,
            dateKey: dateKey,
            interventionID: currentInput.id,
            value: nextManualValue
        )
        let nextSnapshot = replacingInput(
            in: context.snapshot,
            at: index,
            with: nextInput
        )

        let successMessage: String
        switch operation {
        case .increment:
            successMessage = "\(currentInput.name) progress increased."
        case .decrement:
            successMessage = "\(currentInput.name) progress decreased."
        case .reset:
            successMessage = "\(currentInput.name) progress reset."
        }
        let failureMessage = "Could not save dose progress for \(currentInput.name). Reverted."

        return InputMutationResult(
            snapshot: nextSnapshot,
            dailyCheckIns: context.dailyCheckIns,
            dailyDoseProgress: nextDailyDoseProgress,
            interventionCompletionEvents: nextInterventionCompletionEvents,
            interventionDoseSettings: context.interventionDoseSettings,
            activeInterventions: context.activeInterventions,
            patch: .dailyDoseProgressAndCompletionEvents(
                nextDailyDoseProgress,
                nextInterventionCompletionEvents
            ),
            successMessage: successMessage,
            failureMessage: failureMessage
        )
    }

    func updateDoseSettings(
        inputID: String,
        dailyGoal: Double,
        increment: Double,
        context: InputMutationContext
    ) -> InputMutationResult? {
        guard let index = context.snapshot.inputs.firstIndex(where: { $0.id == inputID }) else {
            return nil
        }

        let currentInput = context.snapshot.inputs[index]
        guard currentInput.trackingMode == .dose else {
            return nil
        }
        guard let currentDoseState = currentInput.doseState else {
            return nil
        }

        let safeGoal = max(1, dailyGoal)
        let safeIncrement = max(1, increment)

        let nextDoseState = InputDoseState(
            manualValue: currentDoseState.manualValue,
            healthValue: currentDoseState.healthValue,
            goal: safeGoal,
            increment: safeIncrement,
            unit: currentDoseState.unit
        )
        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: .dose,
            statusText: doseStatusText(for: nextDoseState),
            completion: nextDoseState.completionClamped,
            isCheckedToday: nextDoseState.isGoalMet,
            doseState: nextDoseState,
            completionEvents: currentInput.completionEvents,
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: currentInput.isActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState,
            timeOfDay: currentInput.timeOfDay
        )

        var nextSettings = context.interventionDoseSettings
        nextSettings[inputID] = DoseSettings(dailyGoal: safeGoal, increment: safeIncrement)

        let nextSnapshot = replacingInput(
            in: context.snapshot,
            at: index,
            with: nextInput
        )

        return InputMutationResult(
            snapshot: nextSnapshot,
            dailyCheckIns: context.dailyCheckIns,
            dailyDoseProgress: context.dailyDoseProgress,
            interventionCompletionEvents: context.interventionCompletionEvents,
            interventionDoseSettings: nextSettings,
            activeInterventions: context.activeInterventions,
            patch: .interventionDoseSettings(nextSettings),
            successMessage: "Saved dose settings for \(currentInput.name).",
            failureMessage: "Could not save dose settings for \(currentInput.name). Reverted."
        )
    }

    func toggleActive(
        inputID: String,
        context: InputMutationContext
    ) -> InputMutationResult? {
        guard let index = context.snapshot.inputs.firstIndex(where: { $0.id == inputID }) else {
            return nil
        }

        let currentInput = context.snapshot.inputs[index]
        let nextActive = !currentInput.isActive
        let nextInput = InputStatus(
            id: currentInput.id,
            name: currentInput.name,
            trackingMode: currentInput.trackingMode,
            statusText: currentInput.statusText,
            completion: currentInput.completion,
            isCheckedToday: currentInput.isCheckedToday,
            doseState: currentInput.doseState,
            completionEvents: currentInput.completionEvents,
            graphNodeID: currentInput.graphNodeID,
            classificationText: currentInput.classificationText,
            isActive: nextActive,
            evidenceLevel: currentInput.evidenceLevel,
            evidenceSummary: currentInput.evidenceSummary,
            detailedDescription: currentInput.detailedDescription,
            citationIDs: currentInput.citationIDs,
            externalLink: currentInput.externalLink,
            appleHealthState: currentInput.appleHealthState,
            timeOfDay: currentInput.timeOfDay
        )

        let currentActiveInterventions = context.snapshot.inputs.compactMap { input -> String? in
            input.isActive ? input.id : nil
        }
        let nextActiveInterventions = updatedActiveInterventions(
            from: currentActiveInterventions,
            interventionID: currentInput.id,
            isActive: nextActive
        )
        let nextSnapshot = replacingInput(
            in: context.snapshot,
            at: index,
            with: nextInput
        )

        let successMessage = nextActive
            ? "\(currentInput.name) started tracking."
            : "\(currentInput.name) stopped tracking."
        let failureMessage = "Could not save tracking state for \(currentInput.name). Reverted."

        return InputMutationResult(
            snapshot: nextSnapshot,
            dailyCheckIns: context.dailyCheckIns,
            dailyDoseProgress: context.dailyDoseProgress,
            interventionCompletionEvents: context.interventionCompletionEvents,
            interventionDoseSettings: context.interventionDoseSettings,
            activeInterventions: nextActiveInterventions,
            patch: .activeInterventions(nextActiveInterventions),
            successMessage: successMessage,
            failureMessage: failureMessage
        )
    }

    private func replacingInput(
        in snapshot: DashboardSnapshot,
        at index: Int,
        with nextInput: InputStatus
    ) -> DashboardSnapshot {
        var nextInputs = snapshot.inputs
        nextInputs[index] = nextInput
        return DashboardSnapshot(
            outcomes: snapshot.outcomes,
            outcomeRecords: snapshot.outcomeRecords,
            outcomesMetadata: snapshot.outcomesMetadata,
            situation: snapshot.situation,
            inputs: nextInputs
        )
    }

    private func dayCount(for input: InputStatus) -> Int {
        let scaled = (input.completion * 7.0).rounded()
        return max(0, min(7, Int(scaled)))
    }

    private func updatedDayCount(currentDayCount: Int, currentlyCheckedToday: Bool) -> Int {
        if currentlyCheckedToday {
            return max(0, currentDayCount - 1)
        }

        return min(7, currentDayCount + 1)
    }

    private func statusText(dayCount: Int, checkedToday: Bool) -> String {
        if checkedToday {
            return "Checked today"
        }

        if dayCount > 0 {
            return "\(dayCount)/7 days"
        }

        return "Not checked yet"
    }

    private func doseStatusText(for state: InputDoseState) -> String {
        let percent = Int((state.completionRaw * 100).rounded())
        return "\(DoseValueFormatter.string(from: state.value))/\(DoseValueFormatter.string(from: state.goal)) \(state.unit.displayName) today (\(percent)%)"
    }

    private func updatedDailyCheckIns(
        from current: [String: [String]],
        dateKey: String,
        interventionID: String,
        isChecked: Bool
    ) -> [String: [String]] {
        var next = current
        var interventionIDs = next[dateKey] ?? []

        if isChecked {
            if !interventionIDs.contains(interventionID) {
                interventionIDs.append(interventionID)
            }
        } else {
            interventionIDs.removeAll { $0 == interventionID }
        }

        next[dateKey] = interventionIDs
        return next
    }

    private func updatedDailyDoseProgress(
        from current: [String: [String: Double]],
        dateKey: String,
        interventionID: String,
        value: Double
    ) -> [String: [String: Double]] {
        var next = current
        var progress = next[dateKey] ?? [:]

        if value <= 0 {
            progress.removeValue(forKey: interventionID)
        } else {
            progress[interventionID] = value
        }

        next[dateKey] = progress
        return next
    }

    private func completionEvents(
        for interventionID: String,
        in events: [InterventionCompletionEvent]
    ) -> [InterventionCompletionEvent] {
        events
            .filter { $0.interventionId == interventionID }
            .sorted { lhs, rhs in
                lhs.occurredAt > rhs.occurredAt
            }
    }

    private func appendCompletionEvent(
        _ event: InterventionCompletionEvent,
        to current: [InterventionCompletionEvent],
        maxPerIntervention: Int
    ) -> [InterventionCompletionEvent] {
        var next = current
        next.append(event)

        let matchingIndices = next.indices.filter { index in
            next[index].interventionId == event.interventionId
        }
        let overflowCount = matchingIndices.count - maxPerIntervention
        if overflowCount <= 0 {
            return next
        }

        let oldestIndices = matchingIndices
            .sorted { lhs, rhs in
                if next[lhs].occurredAt == next[rhs].occurredAt {
                    return lhs < rhs
                }
                return next[lhs].occurredAt < next[rhs].occurredAt
            }
            .prefix(overflowCount)
            .sorted(by: >)

        for index in oldestIndices {
            next.remove(at: index)
        }

        return next
    }

    private func updatedActiveInterventions(
        from current: [String],
        interventionID: String,
        isActive: Bool
    ) -> [String] {
        var deduped: [String] = []
        var seen = Set<String>()

        for id in current {
            if id.isEmpty {
                continue
            }
            if seen.insert(id).inserted {
                deduped.append(id)
            }
        }

        deduped.removeAll { $0 == interventionID }
        if isActive {
            deduped.append(interventionID)
        }

        return deduped
    }
}
