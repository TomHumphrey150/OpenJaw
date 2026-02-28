import Foundation

struct HealthPillar: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String

    init(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmed.isEmpty ? "unknown" : trimmed
    }

    init(rawValue: String) {
        self.init(id: rawValue)
    }

    var rawValue: String {
        id
    }

    var displayName: String {
        Self.humanizedTitle(for: id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(id: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }

    private static func humanizedTitle(for identifier: String) -> String {
        let normalized = identifier
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        guard !normalized.isEmpty else {
            return "Unknown"
        }

        var words: [String] = []
        var current = ""

        for character in normalized {
            if character == " " {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }

            if character.isUppercase && !current.isEmpty {
                words.append(current)
                current = String(character)
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            words.append(current)
        }

        return words
            .filter { !$0.isEmpty }
            .map { word in
                let lowercased = word.lowercased()
                guard let first = lowercased.first else {
                    return lowercased
                }
                return String(first).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct HealthPillarDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: HealthPillar
    let title: String
    let rank: Int
}

enum PlanningMode: String, Codable, Equatable, Hashable, Sendable {
    case baseline
    case flare

    var displayName: String {
        switch self {
        case .baseline:
            return "Baseline"
        case .flare:
            return "Flare"
        }
    }
}

enum FoundationRole: String, Codable, Equatable, Hashable, Sendable {
    case blocker
    case maintenance
}

enum HabitPlanningTag: String, Codable, Equatable, Hashable, Sendable {
    case foundation
    case acute
    case blocker
    case maintenance
    case coreFloor
}

struct PreferredTimeWindow: Codable, Equatable, Hashable, Sendable {
    let startMinutes: Int
    let endMinutes: Int

    init(startMinutes: Int, endMinutes: Int) {
        let clampedStart = max(0, min(24 * 60, startMinutes))
        let clampedEnd = max(0, min(24 * 60, endMinutes))
        self.startMinutes = min(clampedStart, clampedEnd)
        self.endMinutes = max(clampedStart, clampedEnd)
    }

    func contains(startMinute: Int) -> Bool {
        startMinute >= startMinutes && startMinute < endMinutes
    }
}

struct HabitPlanningMetadata: Codable, Equatable, Hashable, Sendable {
    let interventionID: String
    let pillars: [HealthPillar]
    let tags: [HabitPlanningTag]
    let acuteTargetNodeIDs: [String]
    let foundationRole: FoundationRole
    let defaultMinutes: Int
    let ladderTemplateID: String
    let preferredWindows: [PreferredTimeWindow]

    init(
        interventionID: String,
        pillars: [HealthPillar],
        tags: [HabitPlanningTag],
        acuteTargetNodeIDs: [String],
        foundationRole: FoundationRole,
        defaultMinutes: Int,
        ladderTemplateID: String,
        preferredWindows: [PreferredTimeWindow] = []
    ) {
        self.interventionID = interventionID
        self.pillars = pillars
        self.tags = tags
        self.acuteTargetNodeIDs = acuteTargetNodeIDs
        self.foundationRole = foundationRole
        self.defaultMinutes = defaultMinutes
        self.ladderTemplateID = ladderTemplateID
        self.preferredWindows = preferredWindows
    }

    private enum CodingKeys: String, CodingKey {
        case interventionID
        case pillars
        case tags
        case acuteTargetNodeIDs
        case foundationRole
        case defaultMinutes
        case ladderTemplateID
        case preferredWindows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interventionID = try container.decode(String.self, forKey: .interventionID)
        pillars = try container.decode([HealthPillar].self, forKey: .pillars)
        tags = try container.decode([HabitPlanningTag].self, forKey: .tags)
        acuteTargetNodeIDs = try container.decode([String].self, forKey: .acuteTargetNodeIDs)
        foundationRole = try container.decode(FoundationRole.self, forKey: .foundationRole)
        defaultMinutes = try container.decode(Int.self, forKey: .defaultMinutes)
        ladderTemplateID = try container.decode(String.self, forKey: .ladderTemplateID)
        preferredWindows = try container.decodeIfPresent([PreferredTimeWindow].self, forKey: .preferredWindows) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interventionID, forKey: .interventionID)
        try container.encode(pillars, forKey: .pillars)
        try container.encode(tags, forKey: .tags)
        try container.encode(acuteTargetNodeIDs, forKey: .acuteTargetNodeIDs)
        try container.encode(foundationRole, forKey: .foundationRole)
        try container.encode(defaultMinutes, forKey: .defaultMinutes)
        try container.encode(ladderTemplateID, forKey: .ladderTemplateID)
        try container.encode(preferredWindows, forKey: .preferredWindows)
    }

    var isFoundation: Bool {
        tags.contains(.foundation)
    }

    var isAcute: Bool {
        tags.contains(.acute)
    }

    var isBlocker: Bool {
        tags.contains(.blocker)
    }

    var isCoreFloor: Bool {
        tags.contains(.coreFloor)
    }
}

struct HabitLadderRung: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let durationMultiplier: Double
    let minimumMinutes: Int
}

struct HabitLadderDefinition: Codable, Equatable, Hashable, Sendable {
    let interventionID: String
    let rungs: [HabitLadderRung]
}

struct HabitPlannerEntryState: Codable, Equatable, Hashable, Sendable {
    let currentRungIndex: Int
    let consecutiveCompletions: Int
    let lastCompletedDayKey: String?
    let lastSuggestedDayKey: String?
    let learnedDurationMinutes: Double?

    static let empty = HabitPlannerEntryState(
        currentRungIndex: 0,
        consecutiveCompletions: 0,
        lastCompletedDayKey: nil,
        lastSuggestedDayKey: nil,
        learnedDurationMinutes: nil
    )
}

struct HabitPlannerState: Codable, Equatable, Hashable, Sendable {
    let entriesByInterventionID: [String: HabitPlannerEntryState]
    let updatedAt: String

    static let empty = HabitPlannerState(entriesByInterventionID: [:], updatedAt: "")
}

enum FlareSensitivity: String, Codable, Equatable, Hashable, Sendable {
    case balanced
    case earlyWarning
    case highConfidence
}

struct DailyTimelineWindow: Codable, Equatable, Hashable, Sendable {
    let wakeMinutes: Int
    let sleepMinutes: Int

    static let `default` = DailyTimelineWindow(
        wakeMinutes: 6 * 60,
        sleepMinutes: 22 * 60
    )

    init(wakeMinutes: Int, sleepMinutes: Int) {
        let clampedWake = max(0, min(24 * 60, wakeMinutes))
        let clampedSleep = max(0, min(24 * 60, sleepMinutes))
        if clampedSleep <= clampedWake {
            self.wakeMinutes = clampedWake
            self.sleepMinutes = min(24 * 60, clampedWake + 60)
            return
        }
        self.wakeMinutes = clampedWake
        self.sleepMinutes = clampedSleep
    }

    var slotStartMinutes: [Int] {
        guard sleepMinutes > wakeMinutes else {
            return []
        }
        var minutes = wakeMinutes
        var slots: [Int] = []
        while minutes < sleepMinutes {
            slots.append(minutes)
            minutes += 15
        }
        return slots
    }
}

struct DailyTimeBudgetState: Codable, Equatable, Hashable, Sendable {
    let timelineWindow: DailyTimelineWindow
    let selectedSlotStartMinutes: [Int]
    let updatedAt: String

    static let `default` = DailyTimeBudgetState(
        timelineWindow: .default,
        selectedSlotStartMinutes: [],
        updatedAt: ""
    )

    init(
        timelineWindow: DailyTimelineWindow,
        selectedSlotStartMinutes: [Int],
        updatedAt: String
    ) {
        self.timelineWindow = timelineWindow
        let allowed = Set(timelineWindow.slotStartMinutes)
        let normalized = Set(
            selectedSlotStartMinutes
                .map { max(0, min(24 * 60, $0)) }
                .filter { $0 % 15 == 0 && allowed.contains($0) }
        )
        self.selectedSlotStartMinutes = normalized.sorted()
        self.updatedAt = updatedAt
    }

    var availableMinutes: Int {
        selectedSlotStartMinutes.count * 15
    }

    static func from(
        availableMinutes: Int,
        updatedAt: String,
        window: DailyTimelineWindow = .default
    ) -> DailyTimeBudgetState {
        let slotCount = max(0, Int((Double(availableMinutes) / 15.0).rounded(.up)))
        let selected = Array(window.slotStartMinutes.prefix(slotCount))
        return DailyTimeBudgetState(
            timelineWindow: window,
            selectedSlotStartMinutes: selected,
            updatedAt: updatedAt
        )
    }
}

struct PlannerPreferencesState: Codable, Equatable, Hashable, Sendable {
    let defaultAvailableMinutes: Int
    let modeOverride: PlanningMode?
    let flareSensitivity: FlareSensitivity
    let updatedAt: String
    let dailyTimeBudgetState: DailyTimeBudgetState?

    init(
        defaultAvailableMinutes: Int,
        modeOverride: PlanningMode?,
        flareSensitivity: FlareSensitivity,
        updatedAt: String,
        dailyTimeBudgetState: DailyTimeBudgetState? = nil
    ) {
        self.defaultAvailableMinutes = defaultAvailableMinutes
        self.modeOverride = modeOverride
        self.flareSensitivity = flareSensitivity
        self.updatedAt = updatedAt
        self.dailyTimeBudgetState = dailyTimeBudgetState
    }

    private enum CodingKeys: String, CodingKey {
        case defaultAvailableMinutes
        case modeOverride
        case flareSensitivity
        case updatedAt
        case dailyTimeBudgetState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultAvailableMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultAvailableMinutes) ?? 90
        modeOverride = try container.decodeIfPresent(PlanningMode.self, forKey: .modeOverride)
        flareSensitivity = try container.decodeIfPresent(FlareSensitivity.self, forKey: .flareSensitivity) ?? .balanced
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        dailyTimeBudgetState = try container.decodeIfPresent(DailyTimeBudgetState.self, forKey: .dailyTimeBudgetState)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultAvailableMinutes, forKey: .defaultAvailableMinutes)
        try container.encodeIfPresent(modeOverride, forKey: .modeOverride)
        try container.encode(flareSensitivity, forKey: .flareSensitivity)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(dailyTimeBudgetState, forKey: .dailyTimeBudgetState)
    }

    static let `default` = PlannerPreferencesState(
        defaultAvailableMinutes: 90,
        modeOverride: nil,
        flareSensitivity: .balanced,
        updatedAt: ""
    )
}

enum HealthLensPreset: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case all
    case foundation
    case acute
    case pillar

    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .foundation:
            return "Foundation"
        case .acute:
            return "Acute"
        case .pillar:
            return "Pillar"
        }
    }
}

struct LensControlPosition: Codable, Equatable, Hashable, Sendable {
    let horizontalRatio: Double
    let verticalRatio: Double

    init(horizontalRatio: Double, verticalRatio: Double) {
        self.horizontalRatio = min(1.0, max(0.0, horizontalRatio))
        self.verticalRatio = min(1.0, max(0.0, verticalRatio))
    }

    static let lowerRight = LensControlPosition(horizontalRatio: 0.88, verticalRatio: 0.84)
    static let midRight = LensControlPosition(horizontalRatio: 0.88, verticalRatio: 0.50)
}

struct LensControlState: Codable, Equatable, Hashable, Sendable {
    let position: LensControlPosition
    let isExpanded: Bool

    static let `default` = LensControlState(
        position: .lowerRight,
        isExpanded: false
    )
}

struct HealthLensState: Codable, Equatable, Hashable, Sendable {
    let preset: HealthLensPreset
    let selectedPillar: HealthPillar?
    let updatedAt: String
    let controlState: LensControlState

    init(
        preset: HealthLensPreset,
        selectedPillar: HealthPillar?,
        updatedAt: String,
        controlState: LensControlState = .default
    ) {
        self.preset = preset
        self.selectedPillar = selectedPillar
        self.updatedAt = updatedAt
        self.controlState = controlState
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case selectedPillar
        case updatedAt
        case controlState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(HealthLensPreset.self, forKey: .preset) ?? .all
        selectedPillar = try container.decodeIfPresent(HealthPillar.self, forKey: .selectedPillar)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        controlState = try container.decodeIfPresent(LensControlState.self, forKey: .controlState) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encodeIfPresent(selectedPillar, forKey: .selectedPillar)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(controlState, forKey: .controlState)
    }

    static let `default` = HealthLensState(
        preset: .all,
        selectedPillar: nil,
        updatedAt: "",
        controlState: .default
    )
}

struct DailyPlanningContext: Sendable {
    let availableMinutes: Int
    let mode: PlanningMode
    let todayKey: String
    let policy: PlanningPolicy
    let inputs: [InputStatus]
    let planningMetadataByInterventionID: [String: HabitPlanningMetadata]
    let ladderByInterventionID: [String: HabitLadderDefinition]
    let plannerState: HabitPlannerState
    let morningStates: [MorningState]
    let nightOutcomes: [NightOutcome]
    let selectedSlotStartMinutes: [Int]
}

struct HabitRungStatus: Equatable, Hashable, Sendable {
    let interventionID: String
    let currentRungID: String
    let currentRungTitle: String
    let targetRungID: String
    let targetRungTitle: String
    let canReportHigherCompletion: Bool
    let higherRungs: [HabitLadderRung]
}

struct PlannedHabitAction: Equatable, Hashable, Sendable, Identifiable {
    let interventionID: String
    let title: String
    let pillars: [HealthPillar]
    let tags: [HabitPlanningTag]
    let selectedRung: HabitLadderRung
    let estimatedMinutes: Int
    let priorityClass: Int
    let priorityScore: Double
    let rationale: String

    var id: String {
        interventionID
    }
}

struct DailyPlanProposal: Equatable, Sendable {
    let mode: PlanningMode
    let availableMinutes: Int
    let usedMinutes: Int
    let actions: [PlannedHabitAction]
    let warnings: [String]
    let nextPlannerState: HabitPlannerState
}

struct FlareDetectionSnapshot: Equatable, Sendable {
    let dayKey: String
    let normalizedSymptomIndex: Double
    let rollingBaseline: Double
}

enum FlareSuggestionDirection: String, Equatable, Sendable {
    case enterFlare
    case exitFlare
}

struct FlareSuggestion: Equatable, Sendable {
    let direction: FlareSuggestionDirection
    let reason: String
    let snapshots: [FlareDetectionSnapshot]
}

struct PlanningLadderPolicy: Codable, Equatable, Hashable, Sendable {
    let fullMultiplier: Double
    let reducedMultiplier: Double
    let minimalMultiplier: Double
    let microMultiplier: Double
    let minimumMinutes: Int

    static let `default` = PlanningLadderPolicy(
        fullMultiplier: 1.0,
        reducedMultiplier: 0.6,
        minimalMultiplier: 0.3,
        microMultiplier: 0.1,
        minimumMinutes: 2
    )
}

struct PlanningPolicy: Codable, Equatable, Hashable, Sendable {
    let policyID: String
    let pillars: [HealthPillarDefinition]
    let coreFloorPillars: [HealthPillar]
    let highPriorityPillarCutoff: Int
    let defaultAvailableMinutes: Int
    let flareEnterThreshold: Double
    let flareExitThreshold: Double
    let flareLookbackDays: Int
    let flareEnterRequiredDays: Int
    let flareExitStableDays: Int
    let ladder: PlanningLadderPolicy

    static let `default` = PlanningPolicy(
        policyID: "planner.v1.fallback",
        pillars: [],
        coreFloorPillars: [],
        highPriorityPillarCutoff: 5,
        defaultAvailableMinutes: 90,
        flareEnterThreshold: 0.65,
        flareExitThreshold: 0.45,
        flareLookbackDays: 3,
        flareEnterRequiredDays: 2,
        flareExitStableDays: 3,
        ladder: .default
    )

    init(
        policyID: String,
        pillars: [HealthPillarDefinition],
        coreFloorPillars: [HealthPillar],
        highPriorityPillarCutoff: Int,
        defaultAvailableMinutes: Int,
        flareEnterThreshold: Double,
        flareExitThreshold: Double,
        flareLookbackDays: Int,
        flareEnterRequiredDays: Int,
        flareExitStableDays: Int,
        ladder: PlanningLadderPolicy
    ) {
        self.policyID = policyID
        self.pillars = Self.normalizedPillars(from: pillars)
        let fallbackCoreFloor = self.pillars.prefix(2).map(\.id)
        self.coreFloorPillars = coreFloorPillars.isEmpty ? fallbackCoreFloor : coreFloorPillars
        let defaultCutoff = max(1, min(5, self.pillars.count))
        self.highPriorityPillarCutoff = max(1, highPriorityPillarCutoff == 0 ? defaultCutoff : highPriorityPillarCutoff)
        self.defaultAvailableMinutes = max(10, defaultAvailableMinutes)
        self.flareEnterThreshold = flareEnterThreshold
        self.flareExitThreshold = flareExitThreshold
        self.flareLookbackDays = max(1, flareLookbackDays)
        self.flareEnterRequiredDays = max(1, flareEnterRequiredDays)
        self.flareExitStableDays = max(1, flareExitStableDays)
        self.ladder = ladder
    }

    var pillarOrder: [HealthPillar] {
        pillars.map(\.id)
    }

    var orderedPillars: [HealthPillarDefinition] {
        pillars
    }

    func title(for pillar: HealthPillar) -> String {
        if let matched = pillars.first(where: { $0.id == pillar }) {
            return matched.title
        }
        return pillar.displayName
    }

    func rank(for pillar: HealthPillar) -> Int {
        guard let index = pillarOrder.firstIndex(of: pillar) else {
            return max(1, pillarOrder.count + 1)
        }
        return index + 1
    }

    private enum CodingKeys: String, CodingKey {
        case policyID
        case pillars
        case pillarOrder
        case coreFloorPillars
        case highPriorityPillarCutoff
        case defaultAvailableMinutes
        case flareEnterThreshold
        case flareExitThreshold
        case flareLookbackDays
        case flareEnterRequiredDays
        case flareExitStableDays
        case ladder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let policyID = try container.decodeIfPresent(String.self, forKey: .policyID) ?? "planner.v1.fallback"

        let decodedPillars = try container.decodeIfPresent([HealthPillarDefinition].self, forKey: .pillars) ?? []
        let legacyOrder = try container.decodeIfPresent([HealthPillar].self, forKey: .pillarOrder) ?? []

        let normalizedPillars: [HealthPillarDefinition]
        if !decodedPillars.isEmpty {
            normalizedPillars = Self.normalizedPillars(from: decodedPillars)
        } else {
            normalizedPillars = legacyOrder.enumerated().map { index, pillar in
                HealthPillarDefinition(
                    id: pillar,
                    title: pillar.displayName,
                    rank: index + 1
                )
            }
        }

        let decodedCoreFloor = try container.decodeIfPresent([HealthPillar].self, forKey: .coreFloorPillars) ?? []
        let defaultAvailableMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultAvailableMinutes) ?? 90
        let flareEnterThreshold = try container.decodeIfPresent(Double.self, forKey: .flareEnterThreshold) ?? 0.65
        let flareExitThreshold = try container.decodeIfPresent(Double.self, forKey: .flareExitThreshold) ?? 0.45
        let flareLookbackDays = try container.decodeIfPresent(Int.self, forKey: .flareLookbackDays) ?? 3
        let flareEnterRequiredDays = try container.decodeIfPresent(Int.self, forKey: .flareEnterRequiredDays) ?? 2
        let flareExitStableDays = try container.decodeIfPresent(Int.self, forKey: .flareExitStableDays) ?? 3
        let ladder = try container.decodeIfPresent(PlanningLadderPolicy.self, forKey: .ladder) ?? .default
        let highPriorityPillarCutoff = try container.decodeIfPresent(Int.self, forKey: .highPriorityPillarCutoff) ?? 0

        self.init(
            policyID: policyID,
            pillars: normalizedPillars,
            coreFloorPillars: decodedCoreFloor,
            highPriorityPillarCutoff: highPriorityPillarCutoff,
            defaultAvailableMinutes: defaultAvailableMinutes,
            flareEnterThreshold: flareEnterThreshold,
            flareExitThreshold: flareExitThreshold,
            flareLookbackDays: flareLookbackDays,
            flareEnterRequiredDays: flareEnterRequiredDays,
            flareExitStableDays: flareExitStableDays,
            ladder: ladder
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(policyID, forKey: .policyID)
        try container.encode(pillars, forKey: .pillars)
        try container.encode(coreFloorPillars, forKey: .coreFloorPillars)
        try container.encode(highPriorityPillarCutoff, forKey: .highPriorityPillarCutoff)
        try container.encode(defaultAvailableMinutes, forKey: .defaultAvailableMinutes)
        try container.encode(flareEnterThreshold, forKey: .flareEnterThreshold)
        try container.encode(flareExitThreshold, forKey: .flareExitThreshold)
        try container.encode(flareLookbackDays, forKey: .flareLookbackDays)
        try container.encode(flareEnterRequiredDays, forKey: .flareEnterRequiredDays)
        try container.encode(flareExitStableDays, forKey: .flareExitStableDays)
        try container.encode(ladder, forKey: .ladder)
    }

    private static func normalizedPillars(from pillars: [HealthPillarDefinition]) -> [HealthPillarDefinition] {
        var seen = Set<HealthPillar>()
        let deduped = pillars.filter { definition in
            seen.insert(definition.id).inserted
        }
        return deduped
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return lhs.id.id < rhs.id.id
            }
            .enumerated()
            .map { index, definition in
                HealthPillarDefinition(
                    id: definition.id,
                    title: definition.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? definition.id.displayName : definition.title,
                    rank: index + 1
                )
            }
    }
}
