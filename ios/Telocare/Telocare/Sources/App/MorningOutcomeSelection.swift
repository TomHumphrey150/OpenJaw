import Foundation

struct MorningOutcomeSelection: Equatable {
    let nightID: String
    let globalSensation: Int?
    let neckTightness: Int?
    let jawSoreness: Int?
    let earFullness: Int?
    let healthAnxiety: Int?
    let stressLevel: Int?
    let morningHeadache: Int?
    let dryMouth: Int?

    init(
        nightID: String,
        globalSensation: Int?,
        neckTightness: Int?,
        jawSoreness: Int?,
        earFullness: Int?,
        healthAnxiety: Int?,
        stressLevel: Int? = nil,
        morningHeadache: Int? = nil,
        dryMouth: Int? = nil
    ) {
        self.nightID = nightID
        self.globalSensation = globalSensation
        self.neckTightness = neckTightness
        self.jawSoreness = jawSoreness
        self.earFullness = earFullness
        self.healthAnxiety = healthAnxiety
        self.stressLevel = stressLevel
        self.morningHeadache = morningHeadache
        self.dryMouth = dryMouth
    }

    static func empty(nightID: String) -> MorningOutcomeSelection {
        MorningOutcomeSelection(
            nightID: nightID,
            globalSensation: nil,
            neckTightness: nil,
            jawSoreness: nil,
            earFullness: nil,
            healthAnxiety: nil,
            stressLevel: nil,
            morningHeadache: nil,
            dryMouth: nil
        )
    }

    var hasAnyValue: Bool {
        globalSensation != nil
            || neckTightness != nil
            || jawSoreness != nil
            || earFullness != nil
            || healthAnxiety != nil
            || stressLevel != nil
            || morningHeadache != nil
            || dryMouth != nil
    }

    var isComplete: Bool {
        isComplete(requiredFields: MorningOutcomeField.legacyFields)
    }

    func isComplete(requiredFields: [MorningOutcomeField]) -> Bool {
        !requiredFields.contains { value(for: $0) == nil }
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
        case .morningHeadache:
            return morningHeadache
        case .dryMouth:
            return dryMouth
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
                stressLevel: stressLevel,
                morningHeadache: morningHeadache,
                dryMouth: dryMouth
            )
        case .neckTightness:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: value,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel,
                morningHeadache: morningHeadache,
                dryMouth: dryMouth
            )
        case .jawSoreness:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: value,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel,
                morningHeadache: morningHeadache,
                dryMouth: dryMouth
            )
        case .earFullness:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: value,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel,
                morningHeadache: morningHeadache,
                dryMouth: dryMouth
            )
        case .healthAnxiety:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: value,
                stressLevel: stressLevel,
                morningHeadache: morningHeadache,
                dryMouth: dryMouth
            )
        case .stressLevel:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: value,
                morningHeadache: morningHeadache,
                dryMouth: dryMouth
            )
        case .morningHeadache:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel,
                morningHeadache: value,
                dryMouth: dryMouth
            )
        case .dryMouth:
            return MorningOutcomeSelection(
                nightID: nightID,
                globalSensation: globalSensation,
                neckTightness: neckTightness,
                jawSoreness: jawSoreness,
                earFullness: earFullness,
                healthAnxiety: healthAnxiety,
                stressLevel: stressLevel,
                morningHeadache: morningHeadache,
                dryMouth: value
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
            morningHeadache: morningHeadache.map(Double.init),
            dryMouth: dryMouth.map(Double.init),
            createdAt: createdAt
        )
    }
}

enum MorningOutcomeField: String, CaseIterable, Identifiable, Hashable {
    case globalSensation
    case neckTightness
    case jawSoreness
    case earFullness
    case healthAnxiety
    case stressLevel
    case morningHeadache
    case dryMouth

    var id: String {
        rawValue
    }

    static let legacyFields: [MorningOutcomeField] = [
        .globalSensation,
        .neckTightness,
        .jawSoreness,
        .earFullness,
        .healthAnxiety,
        .stressLevel,
    ]

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
        case .morningHeadache:
            return "Headache"
        case .dryMouth:
            return "Dry Mouth"
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
        case .morningHeadache:
            return AccessibilityID.exploreMorningHeadachePicker
        case .dryMouth:
            return AccessibilityID.exploreMorningDryMouthPicker
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
        case .morningHeadache:
            return "Morning headache"
        case .dryMouth:
            return "Dry mouth on waking"
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
        case .morningHeadache:
            return "brain"
        case .dryMouth:
            return "drop"
        }
    }
}
