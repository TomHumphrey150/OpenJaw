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
}
