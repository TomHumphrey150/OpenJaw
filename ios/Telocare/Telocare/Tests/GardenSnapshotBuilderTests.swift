import Foundation
import Testing
@testable import Telocare

struct GardenSnapshotBuilderTests {
    @Test func emptyInputsProducesThreeGardensAtZeroBloom() {
        let builder = GardenSnapshotBuilder()
        let snapshots = builder.build(from: [])

        #expect(snapshots.count == 3)
        #expect(snapshots[0].pathway == .upstream)
        #expect(snapshots[1].pathway == .midstream)
        #expect(snapshots[2].pathway == .downstream)

        for garden in snapshots {
            #expect(garden.activeCount == 0)
            #expect(garden.checkedTodayCount == 0)
            #expect(garden.bloomLevel == 0)
            #expect(garden.weeklyAverage == 0)
        }
    }

    @Test func bucketsByPathwayCorrectly() {
        let inputs = [
            makeInput(id: "a", causalPathway: "upstream", isActive: true),
            makeInput(id: "b", causalPathway: "upstream", isActive: true),
            makeInput(id: "c", causalPathway: "midstream", isActive: true),
            makeInput(id: "d", causalPathway: "downstream", isActive: true),
        ]

        let snapshots = GardenSnapshotBuilder().build(from: inputs)

        #expect(snapshots[0].inputIDs == ["a", "b"])
        #expect(snapshots[0].activeCount == 2)
        #expect(snapshots[1].inputIDs == ["c"])
        #expect(snapshots[1].activeCount == 1)
        #expect(snapshots[2].inputIDs == ["d"])
        #expect(snapshots[2].activeCount == 1)
    }

    @Test func nilPathwayDefaultsToMidstream() {
        let inputs = [
            makeInput(id: "a", causalPathway: nil, isActive: true),
        ]

        let snapshots = GardenSnapshotBuilder().build(from: inputs)

        #expect(snapshots[1].inputIDs == ["a"])
        #expect(snapshots[1].activeCount == 1)
        #expect(snapshots[0].inputIDs.isEmpty)
        #expect(snapshots[2].inputIDs.isEmpty)
    }

    @Test func bloomLevelFormulaVerification() {
        // 2 active, 1 checked today. completion = 0.5 (weekly avg for each)
        let inputs = [
            makeInput(id: "a", causalPathway: "upstream", isActive: true, isCheckedToday: true, completion: 0.5),
            makeInput(id: "b", causalPathway: "upstream", isActive: true, isCheckedToday: false, completion: 0.5),
        ]

        let snapshots = GardenSnapshotBuilder().build(from: inputs)
        let garden = snapshots[0]

        // todayRatio = 1/2 = 0.5
        // weeklyAverage = (0.5 + 0.5) / 2 = 0.5
        // bloomLevel = 0.7 * 0.5 + 0.3 * 0.5 = 0.5
        #expect(garden.checkedTodayCount == 1)
        #expect(garden.activeCount == 2)
        #expect(abs(garden.bloomLevel - 0.5) < 0.001)
    }

    @Test func onlyActiveInputsCounted() {
        let inputs = [
            makeInput(id: "a", causalPathway: "upstream", isActive: true, isCheckedToday: true, completion: 1.0),
            makeInput(id: "b", causalPathway: "upstream", isActive: false, isCheckedToday: false, completion: 0.0),
        ]

        let snapshots = GardenSnapshotBuilder().build(from: inputs)
        let garden = snapshots[0]

        #expect(garden.activeCount == 1)
        #expect(garden.checkedTodayCount == 1)
        #expect(garden.inputIDs.count == 2)
        // todayRatio = 1/1 = 1.0
        // weeklyAverage = 1.0
        // bloomLevel = 0.7 * 1.0 + 0.3 * 1.0 = 1.0
        #expect(abs(garden.bloomLevel - 1.0) < 0.001)
    }

    @Test func bloomLevelClampedToUnitRange() {
        let inputs = [
            makeInput(id: "a", causalPathway: "downstream", isActive: true, isCheckedToday: true, completion: 1.5),
        ]

        let snapshots = GardenSnapshotBuilder().build(from: inputs)
        let garden = snapshots[2]

        #expect(garden.bloomLevel <= 1.0)
        #expect(garden.bloomLevel >= 0.0)
    }

    @Test func gardenSnapshotSummaryText() {
        let snapshot = GardenSnapshot(
            pathway: .upstream,
            activeCount: 5,
            checkedTodayCount: 3,
            weeklyAverage: 0.4,
            bloomLevel: 0.5,
            inputIDs: []
        )

        #expect(snapshot.summaryText == "3/5 done")
    }

    @Test func gardenPathwayDisplayProperties() {
        #expect(GardenPathway.upstream.displayName == "Roots")
        #expect(GardenPathway.midstream.displayName == "Canopy")
        #expect(GardenPathway.downstream.displayName == "Bloom")

        #expect(GardenPathway(causalPathway: "upstream") == .upstream)
        #expect(GardenPathway(causalPathway: "midstream") == .midstream)
        #expect(GardenPathway(causalPathway: "downstream") == .downstream)
        #expect(GardenPathway(causalPathway: "unknown") == nil)
        #expect(GardenPathway(causalPathway: nil) == nil)
    }

    // MARK: - Helpers

    private func makeInput(
        id: String,
        causalPathway: String?,
        isActive: Bool,
        isCheckedToday: Bool = false,
        completion: Double = 0
    ) -> InputStatus {
        InputStatus(
            id: id,
            name: id,
            statusText: "",
            completion: completion,
            isCheckedToday: isCheckedToday,
            classificationText: nil,
            isActive: isActive,
            evidenceLevel: nil,
            evidenceSummary: nil,
            detailedDescription: nil,
            citationIDs: [],
            externalLink: nil,
            causalPathway: causalPathway
        )
    }
}
