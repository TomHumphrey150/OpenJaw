import Testing
@testable import Telocare

struct GardenGridLayoutTests {
    private let layout = GardenGridLayout()

    @Test func oneCardRendersSingleLeadingCell() {
        let rows = layout.rows(from: [1])
        #expect(rows == [[1]])
    }

    @Test func twoCardsRenderSingleTwoColumnRow() {
        let rows = layout.rows(from: [1, 2])
        #expect(rows == [[1, 2]])
    }

    @Test func threeCardsRenderTwoRowsWithTrailingSingle() {
        let rows = layout.rows(from: [1, 2, 3])
        #expect(rows == [[1, 2], [3]])
    }

    @Test func fourCardsRenderTwoFullRows() {
        let rows = layout.rows(from: [1, 2, 3, 4])
        #expect(rows == [[1, 2], [3, 4]])
    }

    @Test func fiveCardsRenderTrailingSingleInThirdRow() {
        let rows = layout.rows(from: [1, 2, 3, 4, 5])
        #expect(rows == [[1, 2], [3, 4], [5]])
    }

    @Test func sixCardsRenderThreeFullRows() {
        let rows = layout.rows(from: [1, 2, 3, 4, 5, 6])
        #expect(rows == [[1, 2], [3, 4], [5, 6]])
    }
}
