import Foundation

protocol GuideProjectionBuilding {
    func build(
        graphVersion: String?,
        checkpointVersions: [String],
        pendingConflicts: [GraphPatchConflict],
        pendingPreview: GraphPatchPreview?
    ) -> GuideProjection
}

struct GuideProjectionBuilder: GuideProjectionBuilding {
    func build(
        graphVersion: String?,
        checkpointVersions: [String],
        pendingConflicts: [GraphPatchConflict],
        pendingPreview: GraphPatchPreview?
    ) -> GuideProjection {
        GuideProjection(
            graphVersion: graphVersion,
            checkpointVersions: checkpointVersions,
            pendingConflicts: pendingConflicts,
            pendingPreview: pendingPreview
        )
    }
}

