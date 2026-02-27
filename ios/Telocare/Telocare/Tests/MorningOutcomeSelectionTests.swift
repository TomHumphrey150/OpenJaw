import Testing
@testable import Telocare

struct MorningOutcomeSelectionTests {
    @Test func isCompleteIsFalseWhenAnyFieldIsMissing() {
        let selection = MorningOutcomeSelection(
            nightID: "2026-02-22",
            globalSensation: 6,
            neckTightness: 4,
            jawSoreness: nil,
            earFullness: 3,
            healthAnxiety: 5,
            stressLevel: 4
        )

        #expect(selection.isComplete == false)
    }

    @Test func isCompleteIsTrueWhenAllFieldsArePresent() {
        let selection = MorningOutcomeSelection(
            nightID: "2026-02-22",
            globalSensation: 6,
            neckTightness: 4,
            jawSoreness: 3,
            earFullness: 3,
            healthAnxiety: 5,
            stressLevel: 4
        )

        #expect(selection.isComplete == true)
    }

    @Test func isCompleteUsesRequiredFieldSubset() {
        let selection = MorningOutcomeSelection(
            nightID: "2026-02-22",
            globalSensation: nil,
            neckTightness: 4,
            jawSoreness: 3,
            earFullness: 2,
            healthAnxiety: nil,
            stressLevel: 6,
            morningHeadache: 7,
            dryMouth: 5
        )

        #expect(
            selection.isComplete(requiredFields: [
                .neckTightness,
                .jawSoreness,
                .earFullness,
                .stressLevel,
                .morningHeadache,
                .dryMouth,
            ])
        )
        #expect(selection.isComplete == false)
    }

    @Test func asMorningStateIncludesNewFields() {
        let selection = MorningOutcomeSelection(
            nightID: "2026-02-22",
            globalSensation: 6,
            neckTightness: 4,
            jawSoreness: 3,
            earFullness: 2,
            healthAnxiety: 1,
            stressLevel: 6,
            morningHeadache: 7,
            dryMouth: 5
        )

        let state = selection.asMorningState(createdAt: "2026-02-22T08:00:00Z")

        #expect(state.morningHeadache == 7)
        #expect(state.dryMouth == 5)
    }
}
