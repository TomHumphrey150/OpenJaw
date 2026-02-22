import Foundation

enum MuseArousalHeuristicConstants {
    static let minimumGoodChannels = 3
    static let maximumGoodHsiPrecision = 2.0
    static let minimumDisturbedChannels = 2
    static let accelerometerMotionThresholdG = 0.18
    static let gyroMotionThresholdDps = 15.0
    static let opticsSpikeThresholdMicroamps = 8.0
    static let refractoryWindowSeconds: Int64 = 20
    static let maximumConfidence = 0.95
}
