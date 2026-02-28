import Foundation
import Testing
@testable import Telocare

struct PlanningAndGuideUnitTests {
    @Test func dailyTimeBudgetStateNormalizesSlotsAndComputesMinutes() {
        let state = DailyTimeBudgetState(
            timelineWindow: DailyTimelineWindow(wakeMinutes: 360, sleepMinutes: 420),
            selectedSlotStartMinutes: [350, 360, 375, 390, 999],
            updatedAt: "2026-02-21T00:00:00Z"
        )

        #expect(state.selectedSlotStartMinutes == [360, 375, 390])
        #expect(state.availableMinutes == 45)
    }

    @Test func dailyPlannerPreferredWindowPenaltyChangesRankWithoutExclusion() {
        let planner = DailyPlanner()
        let sleepPillar = HealthPillar(id: "sleep")
        let policy = PlanningPolicy(
            policyID: "planner.v1.test",
            pillars: [
                HealthPillarDefinition(id: sleepPillar, title: "Sleep", rank: 1),
            ],
            coreFloorPillars: [sleepPillar],
            highPriorityPillarCutoff: 1,
            defaultAvailableMinutes: 60,
            flareEnterThreshold: 0.65,
            flareExitThreshold: 0.45,
            flareLookbackDays: 3,
            flareEnterRequiredDays: 2,
            flareExitStableDays: 3,
            ladder: .default
        )

        let inputs = [
            InputStatus(
                id: "morning_action",
                name: "Morning Action",
                trackingMode: .binary,
                statusText: "pending",
                completion: 0,
                isCheckedToday: false,
                graphNodeID: "SLEEP_HYG_TX",
                classificationText: nil,
                isActive: true,
                evidenceLevel: nil,
                evidenceSummary: nil,
                detailedDescription: nil,
                citationIDs: [],
                externalLink: nil
            ),
            InputStatus(
                id: "evening_action",
                name: "Evening Action",
                trackingMode: .binary,
                statusText: "pending",
                completion: 0,
                isCheckedToday: false,
                graphNodeID: "SLEEP_HYG_TX",
                classificationText: nil,
                isActive: true,
                evidenceLevel: nil,
                evidenceSummary: nil,
                detailedDescription: nil,
                citationIDs: [],
                externalLink: nil
            ),
        ]

        let metadataByInterventionID = [
            "morning_action": HabitPlanningMetadata(
                interventionID: "morning_action",
                pillars: [sleepPillar],
                tags: [.foundation, .maintenance],
                acuteTargetNodeIDs: [],
                foundationRole: .maintenance,
                defaultMinutes: 20,
                ladderTemplateID: "general",
                preferredWindows: [PreferredTimeWindow(startMinutes: 360, endMinutes: 720)]
            ),
            "evening_action": HabitPlanningMetadata(
                interventionID: "evening_action",
                pillars: [sleepPillar],
                tags: [.foundation, .maintenance],
                acuteTargetNodeIDs: [],
                foundationRole: .maintenance,
                defaultMinutes: 20,
                ladderTemplateID: "general",
                preferredWindows: [PreferredTimeWindow(startMinutes: 1080, endMinutes: 1320)]
            ),
        ]

        let ladders = [
            "morning_action": HabitLadderDefinition(
                interventionID: "morning_action",
                rungs: [
                    HabitLadderRung(id: "full", title: "Full", durationMultiplier: 1.0, minimumMinutes: 10),
                ]
            ),
            "evening_action": HabitLadderDefinition(
                interventionID: "evening_action",
                rungs: [
                    HabitLadderRung(id: "full", title: "Full", durationMultiplier: 1.0, minimumMinutes: 10),
                ]
            ),
        ]

        let proposal = planner.buildProposal(
            context: DailyPlanningContext(
                availableMinutes: 60,
                mode: .baseline,
                todayKey: "2026-02-21",
                policy: policy,
                inputs: inputs,
                planningMetadataByInterventionID: metadataByInterventionID,
                ladderByInterventionID: ladders,
                plannerState: .empty,
                morningStates: [],
                nightOutcomes: [],
                selectedSlotStartMinutes: [480]
            )
        )

        #expect(proposal.actions.count == 2)
        #expect(proposal.actions.map { $0.interventionID } == ["morning_action", "evening_action"])
    }

    @Test func guideImportDecodeErrorsIncludePathInformation() {
        let codec = GraphPatchJSONCodec()
        let invalidPayload = "{\"schemaVersion\":\"guide-transfer.v1\"}"

        do {
            _ = try codec.decodeGuideExportEnvelope(from: invalidPayload)
            #expect(Bool(false))
        } catch {
            let message = codec.decodeErrorMessage(for: error)
            #expect(message.contains("sections"))
        }
    }
}
