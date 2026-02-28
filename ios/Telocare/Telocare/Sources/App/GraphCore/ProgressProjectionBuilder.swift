import Foundation

protocol ProgressProjectionBuilding {
    func build(
        questionSetState: ProgressQuestionSetState?,
        graphVersion: String?
    ) -> ProgressProjection
}

struct ProgressProjectionBuilder: ProgressProjectionBuilding {
    func build(
        questionSetState: ProgressQuestionSetState?,
        graphVersion: String?
    ) -> ProgressProjection {
        ProgressProjection(
            questionSetState: questionSetState,
            currentGraphVersion: graphVersion
        )
    }
}

