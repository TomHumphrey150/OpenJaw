import Foundation

struct MuseFitReadinessEvaluator {
    static let minimumHeadbandCoverage = 0.80
    static let minimumQualityCoverage = 0.60

    static func evaluate(
        isReceivingData: Bool,
        latestHeadbandOn: Bool?,
        latestHasQualityInputs: Bool?,
        goodChannelCount: Int,
        hsiGoodChannelCount: Int,
        headbandOnCoverage: Double,
        qualityGateCoverage: Double,
        requiredGoodChannels: Int = MuseArousalHeuristicConstants.minimumGoodChannels
    ) -> MuseFitReadinessSnapshot {
        var blockers: [MuseFitReadinessBlocker] = []

        if !isReceivingData {
            blockers.append(.noRecentPackets)
        }
        if latestHeadbandOn == false {
            blockers.append(.headbandOff)
        }
        if latestHasQualityInputs != true {
            blockers.append(.missingQualityInputs)
        }
        if latestHasQualityInputs == true && goodChannelCount < requiredGoodChannels {
            blockers.append(.insufficientGoodChannels)
        }
        if latestHasQualityInputs == true && hsiGoodChannelCount < requiredGoodChannels {
            blockers.append(.poorHsiPrecision)
        }
        if headbandOnCoverage < minimumHeadbandCoverage {
            blockers.append(.lowHeadbandCoverage)
        }
        if qualityGateCoverage < minimumQualityCoverage {
            blockers.append(.lowQualityCoverage)
        }

        return MuseFitReadinessSnapshot(
            isReady: blockers.isEmpty,
            primaryBlocker: blockers.first,
            blockers: blockers,
            goodChannelCount: goodChannelCount,
            hsiGoodChannelCount: hsiGoodChannelCount
        )
    }

    static func sensorStatuses(
        isGoodChannels: [Bool]?,
        hsiPrecisionChannels: [Double]?
    ) -> [MuseSensorFitStatus] {
        MuseEegSensor.allCases.map { sensor in
            let index = sensor.rawValue
            let isGood = isGoodChannels?.value(at: index)
            let hsiPrecision = hsiPrecisionChannels?.value(at: index)
            let passesIsGood = isGood == true
            let passesHsi = hsiPrecision.map {
                $0 <= MuseArousalHeuristicConstants.maximumGoodHsiPrecision
            } ?? false

            return MuseSensorFitStatus(
                sensor: sensor,
                isGood: isGood,
                hsiPrecision: hsiPrecision,
                passesIsGood: passesIsGood,
                passesHsi: passesHsi
            )
        }
    }

    static func goodChannelCount(from channels: [Bool]?) -> Int {
        channels?.prefix(4).filter { $0 }.count ?? 0
    }

    static func hsiGoodChannelCount(from channels: [Double]?) -> Int {
        channels?.prefix(4).filter {
            $0 <= MuseArousalHeuristicConstants.maximumGoodHsiPrecision
        }.count ?? 0
    }
}

private extension Array {
    func value(at index: Int) -> Element? {
        if index < 0 || index >= count {
            return nil
        }

        return self[index]
    }
}
