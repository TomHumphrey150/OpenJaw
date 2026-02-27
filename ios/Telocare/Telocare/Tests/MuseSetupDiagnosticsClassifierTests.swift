import Testing
@testable import Telocare

struct MuseSetupDiagnosticsClassifierTests {
    @Test func classifiesContactOrArtifactWhenContactLikelyAndArtifactsHigh() {
        let diagnosis = MuseSetupDiagnosticsClassifier.classify(
            MuseSetupClassifierInput(
                passRates: MuseSetupPassRates(
                    receivingPackets: 1,
                    headbandCoverage: 0.9,
                    hsiGood3: 0.7,
                    eegGood3: 0,
                    qualityGate: 0
                ),
                artifactRates: MuseSetupArtifactRates(
                    blinkTrueRate: 0.2,
                    jawClenchTrueRate: 0.8
                ),
                hasRecentDisconnectOrTimeoutEvent: false,
                transportWarningCount: 0
            )
        )

        #expect(diagnosis == .contactOrArtifact)
    }

    @Test func classifiesContactOrDrySkinWhenContactLikelyWithoutHighArtifacts() {
        let diagnosis = MuseSetupDiagnosticsClassifier.classify(
            MuseSetupClassifierInput(
                passRates: MuseSetupPassRates(
                    receivingPackets: 1,
                    headbandCoverage: 0.9,
                    hsiGood3: 0.6,
                    eegGood3: 0.05,
                    qualityGate: 0
                ),
                artifactRates: MuseSetupArtifactRates(
                    blinkTrueRate: 0.1,
                    jawClenchTrueRate: 0.2
                ),
                hasRecentDisconnectOrTimeoutEvent: false,
                transportWarningCount: 0
            )
        )

        #expect(diagnosis == .contactOrDrySkin)
    }

    @Test func classifiesTransportUnstableWhenTransportIsUnhealthyWithoutContactSignature() {
        let diagnosis = MuseSetupDiagnosticsClassifier.classify(
            MuseSetupClassifierInput(
                passRates: MuseSetupPassRates(
                    receivingPackets: 0.4,
                    headbandCoverage: 0.2,
                    hsiGood3: 0.1,
                    eegGood3: 0.1,
                    qualityGate: 0.1
                ),
                artifactRates: .zero,
                hasRecentDisconnectOrTimeoutEvent: true,
                transportWarningCount: 0
            )
        )

        #expect(diagnosis == .transportUnstable)
    }

    @Test func classifiesMixedContactAndTransportWhenContactLikelyAndWarningsHigh() {
        let diagnosis = MuseSetupDiagnosticsClassifier.classify(
            MuseSetupClassifierInput(
                passRates: MuseSetupPassRates(
                    receivingPackets: 1,
                    headbandCoverage: 0.9,
                    hsiGood3: 0.8,
                    eegGood3: 0.0,
                    qualityGate: 0.0
                ),
                artifactRates: .zero,
                hasRecentDisconnectOrTimeoutEvent: false,
                transportWarningCount: 3
            )
        )

        #expect(diagnosis == .mixedContactAndTransport)
    }

    @Test func parsesNegativeTimestampPacketTypeCodeFromSdkMessage() {
        let message = "SDK[PACKET] Negative timestamp detected for packet type 41, discarding set (1/5)."
        #expect(MuseSdkWarningParser.negativeTimestampPacketTypeCode(in: message) == 41)
    }

    @Test func ignoresIrrelevantSdkMessagesWhenParsingWarningTypeCode() {
        let message = "SDK[CONNECTOR] CONNECTING --> CONNECTED"
        #expect(MuseSdkWarningParser.negativeTimestampPacketTypeCode(in: message) == nil)
    }

    @Test func identifiesDisconnectAndTimeoutServiceEvents() {
        #expect(MuseSdkWarningParser.isDisconnectOrTimeoutServiceEvent("connection_state=disconnected"))
        #expect(MuseSdkWarningParser.isDisconnectOrTimeoutServiceEvent("Error: StreamTimeoutError: network timeout"))
        #expect(MuseSdkWarningParser.isDisconnectOrTimeoutServiceEvent("connect_outcome=timeout"))
        #expect(MuseSdkWarningParser.isDisconnectOrTimeoutServiceEvent("connection_state=connected") == false)
    }
}
