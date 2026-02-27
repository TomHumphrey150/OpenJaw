import Testing
@testable import Telocare

struct MuseFitReadinessEvaluatorTests {
    @Test func blockerOrderingFollowsConfiguredPriority() {
        let snapshot = MuseFitReadinessEvaluator.evaluate(
            isReceivingData: false,
            latestHeadbandOn: false,
            latestHasQualityInputs: false,
            goodChannelCount: 1,
            hsiGoodChannelCount: 1,
            headbandOnCoverage: 0.2,
            qualityGateCoverage: 0.1
        )

        #expect(snapshot.isReady == false)
        #expect(snapshot.primaryBlocker == .noRecentPackets)
        #expect(snapshot.blockers == [
            .noRecentPackets,
            .headbandOff,
            .missingQualityInputs,
            .lowHeadbandCoverage,
            .lowQualityCoverage,
        ])
    }

    @Test func sensorStatusesDeriveFromIsGoodAndHsiPrecision() {
        let statuses = MuseFitReadinessEvaluator.sensorStatuses(
            isGoodChannels: [true, false, true, false],
            hsiPrecisionChannels: [1, 4, 2, 4]
        )

        #expect(statuses.count == 4)
        #expect(statuses[0].sensor == .eeg1)
        #expect(statuses[0].passesIsGood == true)
        #expect(statuses[0].passesHsi == true)
        #expect(statuses[1].sensor == .eeg2)
        #expect(statuses[1].passesIsGood == false)
        #expect(statuses[1].passesHsi == false)
        #expect(statuses[2].sensor == .eeg3)
        #expect(statuses[2].passesIsGood == true)
        #expect(statuses[2].passesHsi == true)
        #expect(statuses[3].sensor == .eeg4)
        #expect(statuses[3].passesIsGood == false)
        #expect(statuses[3].passesHsi == false)
    }

    @Test func packetTypeCatalogIncludesEegAndOpticsLabels() {
        #expect(MuseDroppedPacketTypeCatalog.label(for: 2) == "eeg")
        #expect(MuseDroppedPacketTypeCatalog.label(for: 41) == "optics")
    }
}
