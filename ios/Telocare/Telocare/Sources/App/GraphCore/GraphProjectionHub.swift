import Foundation
import Observation

struct HabitsProjection: Equatable, Sendable {
    let title: String
    let inputs: [InputStatus]
}

struct ProgressProjection: Equatable, Sendable {
    let questionSetState: ProgressQuestionSetState?
    let currentGraphVersion: String?
}

struct MapProjection: Equatable, Sendable {
    let graphData: CausalGraphData
}

struct GuideProjection: Equatable, Sendable {
    let graphVersion: String?
    let checkpointVersions: [String]
    let pendingConflicts: [GraphPatchConflict]
    let pendingPreview: GraphPatchPreview?
}

@Observable
@MainActor
final class GraphProjectionHub {
    private(set) var habits: HabitsProjection
    private(set) var progress: ProgressProjection
    private(set) var map: MapProjection
    private(set) var guide: GuideProjection

    private let habitsBuilder: HabitsProjectionBuilding
    private let progressBuilder: ProgressProjectionBuilding
    private let mapBuilder: MapProjectionBuilding
    private let guideBuilder: GuideProjectionBuilding

    init(
        inputs: [InputStatus],
        graphData: CausalGraphData,
        graphVersion: String?,
        questionSetState: ProgressQuestionSetState?,
        habitsBuilder: HabitsProjectionBuilding = HabitsProjectionBuilder(),
        progressBuilder: ProgressProjectionBuilding = ProgressProjectionBuilder(),
        mapBuilder: MapProjectionBuilding = MapProjectionBuilder(),
        guideBuilder: GuideProjectionBuilding = GuideProjectionBuilder()
    ) {
        self.habitsBuilder = habitsBuilder
        self.progressBuilder = progressBuilder
        self.mapBuilder = mapBuilder
        self.guideBuilder = guideBuilder

        habits = habitsBuilder.build(inputs: inputs)
        progress = progressBuilder.build(
            questionSetState: questionSetState,
            graphVersion: graphVersion
        )
        map = mapBuilder.build(graphData: graphData)
        guide = guideBuilder.build(
            graphVersion: graphVersion,
            checkpointVersions: [],
            pendingConflicts: [],
            pendingPreview: nil
        )
    }

    func publish(
        inputs: [InputStatus],
        graphData: CausalGraphData,
        graphVersion: String?,
        questionSetState: ProgressQuestionSetState?,
        checkpointVersions: [String],
        pendingConflicts: [GraphPatchConflict],
        pendingPreview: GraphPatchPreview?
    ) {
        habits = habitsBuilder.build(inputs: inputs)
        progress = progressBuilder.build(
            questionSetState: questionSetState,
            graphVersion: graphVersion
        )
        map = mapBuilder.build(graphData: graphData)
        guide = guideBuilder.build(
            graphVersion: graphVersion,
            checkpointVersions: checkpointVersions,
            pendingConflicts: pendingConflicts,
            pendingPreview: pendingPreview
        )
    }
}
