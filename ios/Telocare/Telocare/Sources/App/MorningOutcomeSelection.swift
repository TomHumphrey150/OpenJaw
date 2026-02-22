import Foundation

struct MorningOutcomeSelection: Equatable {
    let nightID: String
    let globalSensation: Int?
    let neckTightness: Int?
    let jawSoreness: Int?
    let earFullness: Int?
    let healthAnxiety: Int?
    let stressLevel: Int?

    init(
        nightID: String,
        globalSensation: Int?,
        neckTightness: Int?,
        jawSoreness: Int?,
        earFullness: Int?,
        healthAnxiety: Int?,
        stressLevel: Int? = nil
    ) {
        self.nightID = nightID
        self.globalSensation = globalSensation
        self.neckTightness = neckTightness
        self.jawSoreness = jawSoreness
        self.earFullness = earFullness
        self.healthAnxiety = healthAnxiety
        self.stressLevel = stressLevel
    }

    static func empty(nightID: String) -> MorningOutcomeSelection {
        MorningOutcomeSelection(
            nightID: nightID,
            globalSensation: nil,
            neckTightness: nil,
            jawSoreness: nil,
            earFullness: nil,
            healthAnxiety: nil,
            stressLevel: nil
        )
    }

    var hasAnyValue: Bool {
        globalSensation != nil
            || neckTightness != nil
            || jawSoreness != nil
            || earFullness != nil
            || healthAnxiety != nil
            || stressLevel != nil
    }

    var isComplete: Bool {
        globalSensation != nil
            && neckTightness != nil
            && jawSoreness != nil
            && earFullness != nil
            && healthAnxiety != nil
            && stressLevel != nil
    }

    func value(for field: MorningOutcomeField) -> Int? {
        switch field {
        case .globalSensation:
            return globalSensation
        case .neckTightness:
            return neckTightness
        case .jawSoreness:
            return jawSoreness
        case .earFullness:
            return earFullness
        case .healthAnxiety:
            return healthAnxiety
        case .stressLevel:
            return stressLevel
        }
    }

    func updating(field: MorningOutcomeField, value: Int?) -> MorningOutcomeSelection {
        switch field {
        case .globalSensation:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: value,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel
            )
        case .neckTightness:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: value,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel
            )
        case .jawSoreness:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: value,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel
            )
        case .earFullness:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: value,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel
            )
        case .healthAnxiety:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: value,
                stressLevel: stressLevel
            )
        case .stressLevel:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: value
            )
        }
    }

    func asMorningState(createdAt: String) -> MorningState {
        MorningState(
            nightId: nightID,
            globalSensation: globalSensation.map(Double.init),
            neckTightness: neckTightness.map(Double.init),
            jawSoreness: jawSoreness.map(Double.init),
            earFullness: earFullness.map(Double.init),
            healthAnxiety: healthAnxiety.map(Double.init),
            stressLevel: stressLevel.map(Double.init),
            createdAt: createdAt
        )
    }
}

enum MorningOutcomeField: String, CaseIterable, Identifiable {
    case globalSensation
    case neckTightness
    case jawSoreness
    case earFullness
    case healthAnxiety
    case stressLevel

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .globalSensation:
            return "Global"
        case .neckTightness:
            return "Neck"
        case .jawSoreness:
            return "Jaw"
        case .earFullness:
            return "Ear"
        case .healthAnxiety:
            return "Anxiety"
        case .stressLevel:
            return "Stress"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .globalSensation:
            return AccessibilityID.exploreMorningGlobalPicker
        case .neckTightness:
            return AccessibilityID.exploreMorningNeckPicker
        case .jawSoreness:
            return AccessibilityID.exploreMorningJawPicker
        case .earFullness:
            return AccessibilityID.exploreMorningEarPicker
        case .healthAnxiety:
            return AccessibilityID.exploreMorningAnxietyPicker
        case .stressLevel:
            return AccessibilityID.exploreMorningStressPicker
        }
    }

    var displayTitle: String {
        switch self {
        case .globalSensation:
            return "Overall feeling"
        case .neckTightness:
            return "Neck tension"
        case .jawSoreness:
            return "Jaw soreness"
        case .earFullness:
            return "Ear fullness"
        case .healthAnxiety:
            return "Worry level"
        case .stressLevel:
            return "Stress level"
        }
    }

    var systemImageName: String {
        switch self {
        case .globalSensation:
            return "figure.stand"
        case .neckTightness:
            return "person.bust"
        case .jawSoreness:
            return "mouth"
        case .earFullness:
            return "ear"
        case .healthAnxiety:
            return "brain.head.profile"
        case .stressLevel:
            return "bolt.heart"
        }
    }
}
