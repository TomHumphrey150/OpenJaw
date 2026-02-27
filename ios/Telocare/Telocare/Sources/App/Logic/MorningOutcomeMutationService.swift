import Foundation

protocol MorningOutcomeMutationService {
    func setMorningOutcomeValue(
        _ value: Int?,
        field: MorningOutcomeField,
        selection: MorningOutcomeSelection,
        morningStates: [MorningState],
        configuredFields: [MorningOutcomeField],
        at now: Date
    ) -> MorningOutcomeMutationResult?
}

struct MorningOutcomeMutationResult {
    let morningOutcomeSelection: MorningOutcomeSelection
    let morningStates: [MorningState]
    let patch: UserDataPatch
    let successMessage: String
    let failureMessage: String
}

struct DefaultMorningOutcomeMutationService: MorningOutcomeMutationService {
    func setMorningOutcomeValue(
        _ value: Int?,
        field: MorningOutcomeField,
        selection: MorningOutcomeSelection,
        morningStates: [MorningState],
        configuredFields: [MorningOutcomeField],
        at now: Date
    ) -> MorningOutcomeMutationResult? {
        guard configuredFields.contains(field) else {
            return nil
        }

        let clampedValue = value.map { max(0, min(10, $0)) }
        let nextSelection = selection.updating(field: field, value: clampedValue)
        guard nextSelection != selection else {
            return nil
        }

        let nextRecord = nextSelection.asMorningState(createdAt: DateKeying.timestamp(from: now))
        let nextMorningStates = upsert(morningState: nextRecord, in: morningStates)

        return MorningOutcomeMutationResult(
            morningOutcomeSelection: nextSelection,
            morningStates: nextMorningStates,
            patch: .morningStates(nextMorningStates),
            successMessage: "Saved morning outcomes for \(nextSelection.nightID).",
            failureMessage: "Could not save morning outcomes. Reverted."
        )
    }

    private func upsert(morningState: MorningState, in existingStates: [MorningState]) -> [MorningState] {
        var mutableStates = existingStates
        guard let existingIndex = mutableStates.firstIndex(where: { $0.nightId == morningState.nightId }) else {
            mutableStates.append(morningState)
            return mutableStates
        }

        let existingCreatedAt = mutableStates[existingIndex].createdAt
        mutableStates[existingIndex] = MorningState(
            nightId: morningState.nightId,
            globalSensation: morningState.globalSensation,
            neckTightness: morningState.neckTightness,
            jawSoreness: morningState.jawSoreness,
            earFullness: morningState.earFullness,
            healthAnxiety: morningState.healthAnxiety,
            stressLevel: morningState.stressLevel,
            morningHeadache: morningState.morningHeadache,
            dryMouth: morningState.dryMouth,
            createdAt: existingCreatedAt
        )
        return mutableStates
    }
}
