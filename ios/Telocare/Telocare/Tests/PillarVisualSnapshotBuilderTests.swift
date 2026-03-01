import Foundation
import Testing
@testable import Telocare

struct PillarVisualSnapshotBuilderTests {
    @Test func kitchenGardenBuildsFromRuntimePillarsWithoutHardcodedIDs() {
        let builder = PillarVisualSnapshotBuilder(calendar: utcCalendar)
        let pillars = [
            HealthPillarDefinition(id: HealthPillar(id: "sleep"), title: "Sleep", rank: 1),
            HealthPillarDefinition(id: HealthPillar(id: "customFocus"), title: "Custom Focus", rank: 2),
        ]
        let inputs = [
            makeInput(id: "habit.custom", isActive: true, isCheckedToday: true),
        ]
        let planningMetadata: [String: HabitPlanningMetadata] = [
            "habit.custom": HabitPlanningMetadata(
                interventionID: "habit.custom",
                pillars: [HealthPillar(id: "customFocus")],
                tags: [.foundation, .maintenance],
                acuteTargetNodeIDs: [],
                foundationRole: .maintenance,
                defaultMinutes: 15,
                ladderTemplateID: "general"
            ),
        ]

        let snapshots = builder.buildKitchenGarden(
            pillars: pillars,
            inputs: inputs,
            planningMetadataByInterventionID: planningMetadata,
            pillarAssignments: []
        )

        #expect(snapshots.count == 2)
        #expect(snapshots[0].pillar.id.id == "sleep")
        #expect(snapshots[0].effortStage == 1)
        #expect(snapshots[1].pillar.id.id == "customFocus")
        #expect(snapshots[1].effortStage == 10)
        #expect(abs(snapshots[1].effortFraction - 1.0) < 0.0001)
    }

    @Test func harvestTableUsesSevenDayRollingWindow() {
        let builder = PillarVisualSnapshotBuilder(calendar: utcCalendar)
        let pillars = [
            HealthPillarDefinition(id: HealthPillar(id: "customFocus"), title: "Custom Focus", rank: 1),
        ]
        let checkIns = [
            makePillarCheckIn(nightID: "2026-03-01", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-28", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-27", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-26", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-25", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-24", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-23", pillarID: "customFocus", value: 4),
            makePillarCheckIn(nightID: "2026-02-22", pillarID: "customFocus", value: 1),
        ]

        let snapshots = builder.buildHarvestTable(
            pillars: pillars,
            inputs: [],
            planningMetadataByInterventionID: [:],
            pillarAssignments: [],
            pillarCheckIns: checkIns
        )

        #expect(snapshots.count == 1)
        #expect(snapshots[0].outcomeSampleCount == 7)
        #expect(snapshots[0].foodStage == 10)
        #expect(abs((snapshots[0].rollingOutcomeFraction ?? 0) - 1.0) < 0.0001)
    }

    @Test func harvestTableSupportsPillarsWithNoCheckIns() {
        let builder = PillarVisualSnapshotBuilder(calendar: utcCalendar)
        let pillars = [
            HealthPillarDefinition(id: HealthPillar(id: "newlyAdded"), title: "Newly Added", rank: 1),
        ]

        let snapshots = builder.buildHarvestTable(
            pillars: pillars,
            inputs: [],
            planningMetadataByInterventionID: [:],
            pillarAssignments: [],
            pillarCheckIns: []
        )

        #expect(snapshots.count == 1)
        #expect(snapshots[0].rollingOutcomeFraction == nil)
        #expect(snapshots[0].outcomeSampleCount == 0)
        #expect(snapshots[0].foodStage == 1)
    }

    @Test func kitchenGardenCountsCrossMappedHabitsForEachMappedPillar() {
        let builder = PillarVisualSnapshotBuilder(calendar: utcCalendar)
        let pillars = [
            HealthPillarDefinition(id: HealthPillar(id: "exercise"), title: "Exercise", rank: 1),
            HealthPillarDefinition(id: HealthPillar(id: "stressManagement"), title: "Stress Management", rank: 2),
        ]
        let inputs = [
            makeInput(id: "habit.nature", isActive: true, isCheckedToday: true),
        ]
        let planningMetadata: [String: HabitPlanningMetadata] = [
            "habit.nature": HabitPlanningMetadata(
                interventionID: "habit.nature",
                pillars: [HealthPillar(id: "exercise"), HealthPillar(id: "stressManagement")],
                tags: [.foundation, .maintenance],
                acuteTargetNodeIDs: [],
                foundationRole: .maintenance,
                defaultMinutes: 15,
                ladderTemplateID: "general"
            ),
        ]

        let snapshots = builder.buildKitchenGarden(
            pillars: pillars,
            inputs: inputs,
            planningMetadataByInterventionID: planningMetadata,
            pillarAssignments: []
        )

        #expect(snapshots.count == 2)
        #expect(snapshots[0].mappedHabitCount == 1)
        #expect(snapshots[1].mappedHabitCount == 1)
        #expect(snapshots[0].activeHabitCount == 1)
        #expect(snapshots[1].activeHabitCount == 1)
        #expect(snapshots[0].completedHabitCount == 1)
        #expect(snapshots[1].completedHabitCount == 1)
    }

    @Test func kitchenGardenUsesPillarAssignmentsWhenPlanningMetadataIsMissing() {
        let builder = PillarVisualSnapshotBuilder(calendar: utcCalendar)
        let pillars = [
            HealthPillarDefinition(id: HealthPillar(id: "neck"), title: "Neck", rank: 1),
        ]
        let inputs = [
            makeInput(id: "habit.neck.mobility", isActive: true, isCheckedToday: false),
        ]
        let assignments = [
            PillarAssignment(
                pillarId: "neck",
                graphNodeIds: [],
                graphEdgeIds: [],
                interventionIds: ["habit.neck.mobility"],
                questionId: nil
            ),
        ]

        let snapshots = builder.buildKitchenGarden(
            pillars: pillars,
            inputs: inputs,
            planningMetadataByInterventionID: [:],
            pillarAssignments: assignments
        )

        #expect(snapshots.count == 1)
        #expect(snapshots[0].mappedHabitCount == 1)
        #expect(snapshots[0].activeHabitCount == 1)
        #expect(snapshots[0].completedHabitCount == 0)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeInput(id: String, isActive: Bool, isCheckedToday: Bool) -> InputStatus {
        InputStatus(
            id: id,
            name: id,
            statusText: "",
            completion: isCheckedToday ? 1.0 : 0.0,
            isCheckedToday: isCheckedToday,
            classificationText: nil,
            isActive: isActive,
            evidenceLevel: nil,
            evidenceSummary: nil,
            detailedDescription: nil,
            citationIDs: [],
            externalLink: nil
        )
    }

    private func makePillarCheckIn(nightID: String, pillarID: String, value: Int) -> PillarCheckIn {
        PillarCheckIn(
            nightId: nightID,
            responsesByPillarId: [pillarID: value],
            createdAt: "\(nightID)T07:00:00.000Z",
            graphAssociation: nil
        )
    }
}
