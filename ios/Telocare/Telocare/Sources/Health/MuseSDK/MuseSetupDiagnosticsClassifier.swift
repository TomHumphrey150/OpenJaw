import Foundation

struct MuseSetupClassifierInput: Equatable, Sendable {
    let passRates: MuseSetupPassRates
    let artifactRates: MuseSetupArtifactRates
    let hasRecentDisconnectOrTimeoutEvent: Bool
    let transportWarningCount: Int
}

struct MuseSetupDiagnosticsClassifier {
    static let windowSeconds = 30
    static let minimumReceivingPacketsForHealthyTransport = 0.90
    static let contactLikelyMaximumEegGood3 = 0.10
    static let contactLikelyMinimumHsiGood3 = 0.40
    static let contactLikelyMaximumQualityGate = 0.10
    static let artifactHighThreshold = 0.50
    static let transportWarningHighCount = 3

    static func classify(_ input: MuseSetupClassifierInput) -> MuseSetupDiagnosis {
        let transportHealthy = input.passRates.receivingPackets >= minimumReceivingPacketsForHealthyTransport
            && !input.hasRecentDisconnectOrTimeoutEvent

        let contactLikely = input.passRates.eegGood3 < contactLikelyMaximumEegGood3
            && input.passRates.hsiGood3 >= contactLikelyMinimumHsiGood3
            && input.passRates.qualityGate < contactLikelyMaximumQualityGate

        let artifactHigh = input.artifactRates.blinkTrueRate >= artifactHighThreshold
            || input.artifactRates.jawClenchTrueRate >= artifactHighThreshold

        let transportWarningsHigh = input.transportWarningCount >= transportWarningHighCount

        if contactLikely && transportWarningsHigh {
            return .mixedContactAndTransport
        }

        if !transportHealthy && !contactLikely {
            return .transportUnstable
        }

        if contactLikely && artifactHigh {
            return .contactOrArtifact
        }

        if contactLikely {
            return .contactOrDrySkin
        }

        if !transportHealthy {
            return .transportUnstable
        }

        return .unknown
    }
}

struct MuseSdkWarningParser {
    static func negativeTimestampPacketTypeCode(in message: String) -> Int? {
        let marker = "Negative timestamp detected for packet type "
        guard let markerRange = message.range(of: marker) else {
            return nil
        }

        let suffix = message[markerRange.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty else {
            return nil
        }

        return Int(digits)
    }

    static func isDisconnectOrTimeoutServiceEvent(_ message: String) -> Bool {
        if message.contains("connection_state=disconnected") {
            return true
        }

        let lowercase = message.lowercased()
        return lowercase.contains("timeout")
    }
}
