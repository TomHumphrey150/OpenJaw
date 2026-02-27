import Foundation

protocol MuseSessionCoordinator {
    func recordingReliability(
        fitGuidance: MuseFitGuidance,
        startedWithFitOverride: Bool
    ) -> MuseRecordingReliability

    func resolveSessionError(
        _ error: Error,
        fallback: String
    ) -> MuseSessionMutationResult
}

struct MuseSessionMutationResult {
    let connectionState: MuseConnectionState?
    let message: String
}

struct DefaultMuseSessionCoordinator: MuseSessionCoordinator {
    func recordingReliability(
        fitGuidance: MuseFitGuidance,
        startedWithFitOverride: Bool
    ) -> MuseRecordingReliability {
        if fitGuidance == .insufficientSignal {
            return .insufficientSignal
        }
        if startedWithFitOverride || fitGuidance == .adjustHeadband {
            return .limitedFit
        }

        return .verifiedFit
    }

    func resolveSessionError(
        _ error: Error,
        fallback: String
    ) -> MuseSessionMutationResult {
        guard let museError = error as? MuseSessionServiceError else {
            return MuseSessionMutationResult(
                connectionState: .failed(fallback),
                message: fallback
            )
        }

        switch museError {
        case .unavailable:
            return MuseSessionMutationResult(
                connectionState: .failed("Muse integration is unavailable in this build."),
                message: "Muse integration is unavailable in this build."
            )
        case .noHeadbandFound:
            return MuseSessionMutationResult(
                connectionState: .disconnected,
                message: "No Muse headbands found."
            )
        case .notConnected:
            return MuseSessionMutationResult(
                connectionState: .disconnected,
                message: "Muse is not connected."
            )
        case .needsLicense:
            return MuseSessionMutationResult(
                connectionState: .needsLicense,
                message: "Muse license is required before connecting."
            )
        case .needsUpdate:
            return MuseSessionMutationResult(
                connectionState: .needsUpdate,
                message: "Muse headband firmware update is required."
            )
        case .unsupportedHeadbandModel:
            return MuseSessionMutationResult(
                connectionState: .failed("This Muse headband model is not supported. Use Muse S Athena (MS-03)."),
                message: "This Muse headband model is not supported. Use Muse S Athena (MS-03)."
            )
        case .alreadyRecording:
            return MuseSessionMutationResult(
                connectionState: nil,
                message: "Recording is already in progress."
            )
        case .notRecording:
            return MuseSessionMutationResult(
                connectionState: nil,
                message: "No active recording to stop."
            )
        }
    }
}
