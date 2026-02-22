# Tension Check Widget — Full Implementation Plan

## Context

Stress is a primary driver of the jaw grinding / TMD cycle. To break it, we need to track tension levels throughout the day and intervene when they're high. The app currently only captures morning outcomes (once per day via `MorningState`). This feature adds an **iOS home screen widget** that acts as a quick, discreet "Tension check" — the user taps an emoji (same 😌→😫 scale used in `EmojiRatingPicker`), and if tension is high (7 or 10), the widget suggests a micro-intervention (e.g. diaphragmatic breathing) with a checkmark to complete it. **All interactions stay on the home screen** — no app launch needed.

The framing is physical/medical ("Tension check" with a body icon) so it reads like a standard health app if a colleague sees the screen. Data syncs to Supabase when the main app next opens.

### Technical approach

iOS interactive widgets (iOS 17+) support `Button` and `Toggle` controls via the AppIntents framework. Each tap executes an `AppIntent.perform()` method which writes state to shared App Group `UserDefaults`, then calls `WidgetCenter.shared.reloadTimelines(ofKind:)` to refresh the widget UI. There's a ~1-2 second delay between tap and re-render, which is acceptable for this use case.

The widget extension runs in a separate process and cannot access main app code, so shared types live in a `TelocareShared` framework that both targets depend on.

---

## Widget State Machine

```
              ┌─────────┐
  low stress  │         │  auto-reset (5s timeline entry)
 ──────────>  │ PICKER  │ <──────────────────┐
              │         │                    │
              └────┬────┘                    │
                   │ high stress (7 or 10)   │
                   v                         │
            ┌─────────────┐                  │
            │ SUGGESTION  │                  │
            │ "Try 10     │──── skip ────────┤
            │  breaths"   │                  │
            └──────┬──────┘                  │
                   │ tap checkmark           │
                   v                         │
            ┌─────────────┐                  │
            │ COMPLETED   │──── 5 sec ───────┘
            │ "Logged ✓"  │
            └─────────────┘
```

- **Low stress tap (0, 3, 5):** Records check-in, widget stays on picker (brief visual acknowledgment)
- **High stress tap (7, 10):** Records check-in, widget transitions to suggestion view
- **Checkmark tap:** Marks intervention completed on the check-in, shows completion view
- **Skip tap:** Returns to picker without marking intervention done
- **Auto-reset:** Completed view returns to picker after 5 seconds via a future timeline entry

---

## Directory Structure (new files)

```
/Users/tomhumphrey/src/OpenJaw/ios/Telocare/
├── TelocareShared/
│   ├── Sources/
│   │   ├── StressCheckIn.swift          # Core data model
│   │   ├── TensionLevel.swift           # Enum mapping emojis to values
│   │   ├── WidgetPhase.swift            # Widget state machine enum
│   │   ├── InterventionSuggestion.swift # Hardcoded suggestion pool
│   │   └── WidgetDataStore.swift        # App Group UserDefaults bridge
│   └── Tests/
│       ├── StressCheckInTests.swift
│       └── WidgetDataStoreTests.swift
├── TelocareWidget/
│   ├── Sources/
│   │   ├── TelocareWidgetBundle.swift   # @main entry point
│   │   ├── TensionCheckWidget.swift     # Widget configuration
│   │   ├── TensionCheckTimelineProvider.swift
│   │   ├── TensionCheckWidgetEntryView.swift  # All 3 phase views
│   │   ├── RecordTensionIntent.swift    # AppIntent: emoji tap
│   │   ├── MarkInterventionDoneIntent.swift   # AppIntent: checkmark
│   │   └── ResetWidgetIntent.swift      # AppIntent: skip/reset
│   └── TelocareWidget.entitlements
```

---

## Step 1: Create TelocareShared Framework

### 1a. `TelocareShared/Sources/StressCheckIn.swift`

The core data model for a single tension check-in. Follows the same pattern as `MorningState` in `UserDataDocument.swift:386` — simple `Codable` struct with an ISO8601 timestamp. Unlike `MorningState` (one per day), this supports multiple entries per day.

```swift
import Foundation

public struct StressCheckIn: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let tensionLevel: Int               // 0, 3, 5, 7, or 10
    public let suggestedInterventionId: String? // e.g. "diaphragm_breathing"; nil if low stress
    public let interventionCompleted: Bool      // true if user tapped checkmark
    public let createdAt: String               // ISO8601 timestamp

    public init(
        id: String = UUID().uuidString,
        tensionLevel: Int,
        suggestedInterventionId: String? = nil,
        interventionCompleted: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.tensionLevel = tensionLevel
        self.suggestedInterventionId = suggestedInterventionId
        self.interventionCompleted = interventionCompleted
        self.createdAt = createdAt
    }
}
```

### 1b. `TelocareShared/Sources/TensionLevel.swift`

Maps directly to the existing emoji scale in `EmojiRatingPicker.swift:7-13`. Same values (0/3/5/7/10), same emojis (😌🙂😐😣😫).

```swift
import Foundation

public enum TensionLevel: Int, CaseIterable, Identifiable, Codable, Sendable {
    case none = 0
    case mild = 3
    case moderate = 5
    case strong = 7
    case severe = 10

    public var id: Int { rawValue }

    public var emoji: String {
        switch self {
        case .none:     "😌"
        case .mild:     "🙂"
        case .moderate: "😐"
        case .strong:   "😣"
        case .severe:   "😫"
        }
    }

    public var label: String {
        switch self {
        case .none:     "None"
        case .mild:     "Mild"
        case .moderate: "Mod"
        case .strong:   "High"
        case .severe:   "Bad"
        }
    }

    /// Stress levels 7+ trigger an intervention suggestion in the widget.
    public var triggersSuggestion: Bool {
        rawValue >= 7
    }
}
```

### 1c. `TelocareShared/Sources/WidgetPhase.swift`

The widget's visual state. Persisted in App Group UserDefaults so the `TimelineProvider` can render the correct view.

```swift
import Foundation

/// Widget cycles: .picker → .suggestion → .completed → .picker
/// Low-stress taps stay on .picker (no suggestion phase).
public enum WidgetPhase: Codable, Equatable, Sendable {
    case picker
    case suggestion(
        interventionId: String,
        interventionName: String,
        actionLabel: String,
        checkInId: String
    )
    case completed(interventionName: String, checkInId: String)
}
```

### 1d. `TelocareShared/Sources/InterventionSuggestion.swift`

Hardcoded pool of quick micro-interventions. The widget has no network access at tap-time, so suggestions are embedded. These map to real intervention IDs from `interventions.json` — specifically `diaphragm_breathing` (line ~65 in interventions.json), plus a couple of others.

```swift
import Foundation

public struct InterventionSuggestion: Sendable {
    public let interventionId: String
    public let name: String
    public let actionLabel: String

    public static let suggestions: [InterventionSuggestion] = [
        InterventionSuggestion(
            interventionId: "diaphragm_breathing",
            name: "Diaphragm Breathing",
            actionLabel: "Try 10 slow breaths (4s in, 6s out)"
        ),
        InterventionSuggestion(
            interventionId: "jaw_relaxation",
            name: "Jaw Release",
            actionLabel: "Let your jaw hang loose for 30 seconds"
        ),
        InterventionSuggestion(
            interventionId: "mindfulness_minutes",
            name: "Body Scan",
            actionLabel: "Do a 2-minute body scan"
        ),
    ]

    /// Picks a suggestion, rotating to avoid repeating the last one shown.
    public static func pick(excluding lastId: String? = nil) -> InterventionSuggestion {
        let filtered = suggestions.filter { $0.interventionId != lastId }
        let pool = filtered.isEmpty ? suggestions : filtered
        return pool.randomElement() ?? suggestions[0]
    }
}
```

### 1e. `TelocareShared/Sources/WidgetDataStore.swift`

The bridge between widget extension and main app. The widget writes check-ins and its visual state here. The main app reads pending check-ins on foreground, syncs them to Supabase, then clears.

```swift
import Foundation

public final class WidgetDataStore: Sendable {
    public static let appGroupID = "group.dev.tuist.Telocare"

    private static let pendingCheckInsKey = "widget_pending_stress_check_ins"
    private static let widgetPhaseKey = "widget_current_phase"
    private static let lastSuggestionIdKey = "widget_last_suggestion_id"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupID)
            ?? .standard
    }

    // MARK: - Pending check-ins (widget writes, app reads + clears)

    public func appendCheckIn(_ checkIn: StressCheckIn) {
        var existing = pendingCheckIns()
        existing.append(checkIn)
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.pendingCheckInsKey)
        }
    }

    public func pendingCheckIns() -> [StressCheckIn] {
        guard let data = defaults.data(forKey: Self.pendingCheckInsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([StressCheckIn].self, from: data)) ?? []
    }

    public func clearPendingCheckIns() {
        defaults.removeObject(forKey: Self.pendingCheckInsKey)
    }

    /// Replace the full pending array (used when updating a check-in's
    /// interventionCompleted flag in MarkInterventionDoneIntent).
    public func replacePendingCheckIns(_ checkIns: [StressCheckIn]) {
        if let data = try? JSONEncoder().encode(checkIns) {
            defaults.set(data, forKey: Self.pendingCheckInsKey)
        }
    }

    // MARK: - Widget phase (read by TimelineProvider to render correct view)

    public func widgetPhase() -> WidgetPhase {
        guard let data = defaults.data(forKey: Self.widgetPhaseKey),
              let phase = try? JSONDecoder().decode(WidgetPhase.self, from: data) else {
            return .picker
        }
        return phase
    }

    public func setWidgetPhase(_ phase: WidgetPhase) {
        if let data = try? JSONEncoder().encode(phase) {
            defaults.set(data, forKey: Self.widgetPhaseKey)
        }
    }

    // MARK: - Last suggestion tracking (for rotation)

    public func lastSuggestionId() -> String? {
        defaults.string(forKey: Self.lastSuggestionIdKey)
    }

    public func setLastSuggestionId(_ id: String) {
        defaults.set(id, forKey: Self.lastSuggestionIdKey)
    }
}
```

---

## Step 2: Create TelocareWidget Extension

### 2a. `TelocareWidget/Sources/TelocareWidgetBundle.swift`

```swift
import SwiftUI
import WidgetKit

@main
struct TelocareWidgetBundle: WidgetBundle {
    var body: some Widget {
        TensionCheckWidget()
    }
}
```

### 2b. `TelocareWidget/Sources/TensionCheckWidget.swift`

```swift
import SwiftUI
import WidgetKit

struct TensionCheckWidget: Widget {
    let kind = "TensionCheckWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TensionCheckTimelineProvider()
        ) { entry in
            TensionCheckWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tension Check")
        .description("Quick tension check-in throughout the day.")
        .supportedFamilies([.systemMedium])
    }
}
```

Using `systemMedium` (roughly 329×155 points) which comfortably fits 5 emoji buttons in a row with labels.

### 2c. `TelocareWidget/Sources/TensionCheckTimelineProvider.swift`

```swift
import WidgetKit
import TelocareShared

struct TensionCheckEntry: TimelineEntry {
    let date: Date
    let phase: WidgetPhase
}

struct TensionCheckTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> TensionCheckEntry {
        TensionCheckEntry(date: .now, phase: .picker)
    }

    func getSnapshot(in context: Context, completion: @escaping (TensionCheckEntry) -> Void) {
        let store = WidgetDataStore()
        completion(TensionCheckEntry(date: .now, phase: store.widgetPhase()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TensionCheckEntry>) -> Void
    ) {
        let store = WidgetDataStore()
        let phase = store.widgetPhase()

        switch phase {
        case .completed:
            // Show "Logged" for 5 seconds, then auto-reset to picker.
            // We pre-set the stored phase to .picker so the next read gets it right.
            let now = Date()
            let resetDate = now.addingTimeInterval(5)
            let entries = [
                TensionCheckEntry(date: now, phase: phase),
                TensionCheckEntry(date: resetDate, phase: .picker),
            ]
            store.setWidgetPhase(.picker)
            completion(Timeline(entries: entries, policy: .after(resetDate)))

        case .suggestion:
            // Stay on suggestion until user acts. Safety refresh after 5 minutes
            // in case the user walks away.
            let refreshDate = Date().addingTimeInterval(300)
            let entry = TensionCheckEntry(date: .now, phase: phase)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))

        case .picker:
            // Default idle state. Refresh every 30 minutes to keep widget alive.
            let refreshDate = Date().addingTimeInterval(1800)
            let entry = TensionCheckEntry(date: .now, phase: .picker)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }
}
```

### 2d. `TelocareWidget/Sources/TensionCheckWidgetEntryView.swift`

The main widget view. Renders one of three phases. Uses the Telocare design system colors inline (can't import the main app's `TelocareTheme` since we're in the widget extension, but we replicate the coral/peach palette).

```swift
import SwiftUI
import WidgetKit
import TelocareShared

struct TensionCheckWidgetEntryView: View {
    let entry: TensionCheckEntry

    // Telocare palette (replicated from TelocareTheme.swift)
    private let coral = Color(red: 1.0, green: 0.44, blue: 0.35)
    private let peach = Color(red: 1.0, green: 0.87, blue: 0.82)
    private let charcoal = Color(red: 0.20, green: 0.20, blue: 0.22)
    private let warmGray = Color(red: 0.60, green: 0.58, blue: 0.56)

    var body: some View {
        switch entry.phase {
        case .picker:
            pickerView
        case .suggestion(_, _, let actionLabel, let checkInId):
            suggestionView(actionLabel: actionLabel, checkInId: checkInId)
        case .completed(let name, _):
            completedView(name: name)
        }
    }

    // MARK: - Picker Phase

    @ViewBuilder
    private var pickerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(coral)
                Text("Tension check")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(charcoal)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(TensionLevel.allCases) { level in
                    Button(intent: RecordTensionIntent(level: level.rawValue)) {
                        VStack(spacing: 2) {
                            Text(level.emoji)
                                .font(.system(size: 24))
                            Text(level.label)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(warmGray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
    }

    // MARK: - Suggestion Phase

    @ViewBuilder
    private func suggestionView(actionLabel: String, checkInId: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 28))
                .foregroundStyle(coral)

            Text(actionLabel)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(charcoal)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(intent: MarkInterventionDoneIntent(checkInId: checkInId)) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(coral)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(intent: ResetWidgetIntent()) {
                    Text("Skip")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(warmGray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    // MARK: - Completed Phase

    @ViewBuilder
    private func completedView(name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0.52, green: 0.76, blue: 0.56)) // success green
            Text("Logged")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(charcoal)
        }
        .padding()
    }
}
```

### 2e. `TelocareWidget/Sources/RecordTensionIntent.swift`

The primary AppIntent — triggered when the user taps an emoji button.

```swift
import AppIntents
import WidgetKit
import TelocareShared

struct RecordTensionIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Tension Level"

    @Parameter(title: "Level")
    var level: Int

    init() { self.level = 5 }
    init(level: Int) { self.level = level }

    func perform() async throws -> some IntentResult {
        let store = WidgetDataStore()
        let tensionLevel = TensionLevel(rawValue: level) ?? .moderate

        if tensionLevel.triggersSuggestion {
            // High stress → pick an intervention suggestion
            let lastId = store.lastSuggestionId()
            let suggestion = InterventionSuggestion.pick(excluding: lastId)
            store.setLastSuggestionId(suggestion.interventionId)

            let checkIn = StressCheckIn(
                tensionLevel: level,
                suggestedInterventionId: suggestion.interventionId,
                interventionCompleted: false
            )
            store.appendCheckIn(checkIn)
            store.setWidgetPhase(.suggestion(
                interventionId: suggestion.interventionId,
                interventionName: suggestion.name,
                actionLabel: suggestion.actionLabel,
                checkInId: checkIn.id
            ))
        } else {
            // Low stress → just record and stay on picker
            let checkIn = StressCheckIn(
                tensionLevel: level,
                suggestedInterventionId: nil,
                interventionCompleted: false
            )
            store.appendCheckIn(checkIn)
            store.setWidgetPhase(.picker)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "TensionCheckWidget")
        return .result()
    }
}
```

### 2f. `TelocareWidget/Sources/MarkInterventionDoneIntent.swift`

Triggered when the user taps the checkmark button on the suggestion view.

```swift
import AppIntents
import WidgetKit
import TelocareShared

struct MarkInterventionDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Intervention"

    @Parameter(title: "CheckIn ID")
    var checkInId: String

    init() { self.checkInId = "" }
    init(checkInId: String) { self.checkInId = checkInId }

    func perform() async throws -> some IntentResult {
        let store = WidgetDataStore()

        // Update the matching check-in to mark intervention as completed
        var pending = store.pendingCheckIns()
        if let idx = pending.firstIndex(where: { $0.id == checkInId }) {
            let original = pending[idx]
            pending[idx] = StressCheckIn(
                id: original.id,
                tensionLevel: original.tensionLevel,
                suggestedInterventionId: original.suggestedInterventionId,
                interventionCompleted: true,
                createdAt: original.createdAt
            )
            store.replacePendingCheckIns(pending)
        }

        // Read current phase to get intervention name for the completed view
        let currentPhase = store.widgetPhase()
        let interventionName: String
        if case .suggestion(_, let name, _, _) = currentPhase {
            interventionName = name
        } else {
            interventionName = "Intervention"
        }

        store.setWidgetPhase(.completed(
            interventionName: interventionName,
            checkInId: checkInId
        ))

        WidgetCenter.shared.reloadTimelines(ofKind: "TensionCheckWidget")
        return .result()
    }
}
```

### 2g. `TelocareWidget/Sources/ResetWidgetIntent.swift`

Triggered by the "Skip" button, or could be called programmatically.

```swift
import AppIntents
import WidgetKit
import TelocareShared

struct ResetWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Reset Widget"

    func perform() async throws -> some IntentResult {
        let store = WidgetDataStore()
        store.setWidgetPhase(.picker)
        WidgetCenter.shared.reloadTimelines(ofKind: "TensionCheckWidget")
        return .result()
    }
}
```

### 2h. `TelocareWidget/TelocareWidget.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.dev.tuist.Telocare</string>
    </array>
</dict>
</plist>
```

---

## Step 3: Update Project.swift

**File:** `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Project.swift`

Add 3 new targets and update 2 existing ones. The full targets array becomes:

```swift
targets: [
    // --- Existing: main app (MODIFIED — add TelocareShared + TelocareWidget deps) ---
    .target(
        name: "Telocare",
        destinations: .iOS,
        product: .app,
        bundleId: "dev.tuist.Telocare",
        infoPlist: .extendingDefault(with: [ /* unchanged */ ]),
        buildableFolders: [
            "Telocare/Sources",
            "Telocare/Resources",
        ],
        entitlements: .file(path: .relativeToRoot("Telocare/Telocare.entitlements")),
        dependencies: [
            .external(name: "Supabase"),
            .target(name: "TelocareShared"),  // NEW
            .target(name: "TelocareWidget"),  // NEW — embeds widget in app bundle
        ],
        settings: strictSettings
    ),

    // --- Existing: unit tests (MODIFIED — add TelocareShared dep) ---
    .target(
        name: "TelocareTests",
        destinations: .iOS,
        product: .unitTests,
        bundleId: "dev.tuist.TelocareTests",
        infoPlist: .default,
        buildableFolders: ["Telocare/Tests"],
        dependencies: [
            .target(name: "Telocare"),
            .target(name: "TelocareShared"),  // NEW
        ],
        settings: strictSettings
    ),

    // --- Existing: UI tests (unchanged) ---
    .target(
        name: "TelocareUITests",
        // ... unchanged ...
    ),

    // --- NEW: shared framework ---
    .target(
        name: "TelocareShared",
        destinations: .iOS,
        product: .framework,
        bundleId: "dev.tuist.Telocare.Shared",
        infoPlist: .default,
        buildableFolders: ["TelocareShared/Sources"],
        dependencies: [],
        settings: strictSettings
    ),

    // --- NEW: widget extension ---
    .target(
        name: "TelocareWidget",
        destinations: .iOS,
        product: .appExtension,
        bundleId: "dev.tuist.Telocare.Widget",
        infoPlist: .extendingDefault(with: [
            "NSExtension": [
                "NSExtensionPointIdentifier":
                    "com.apple.widgetkit-extension",
            ]
        ]),
        buildableFolders: ["TelocareWidget/Sources"],
        entitlements: .file(
            path: .relativeToRoot("TelocareWidget/TelocareWidget.entitlements")
        ),
        dependencies: [
            .target(name: "TelocareShared"),
        ],
        settings: strictSettings
    ),

    // --- NEW: shared framework tests ---
    .target(
        name: "TelocareSharedTests",
        destinations: .iOS,
        product: .unitTests,
        bundleId: "dev.tuist.Telocare.SharedTests",
        infoPlist: .default,
        buildableFolders: ["TelocareShared/Tests"],
        dependencies: [.target(name: "TelocareShared")],
        settings: strictSettings
    ),
]
```

---

## Step 4: Add App Group Entitlement to Main App

**File:** `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Telocare.entitlements`

Current contents (HealthKit only):
```xml
<dict>
    <key>com.apple.developer.healthkit</key>
    <true/>
</dict>
```

Add App Group alongside HealthKit:
```xml
<dict>
    <key>com.apple.developer.healthkit</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.dev.tuist.Telocare</string>
    </array>
</dict>
```

---

## Step 5: Add stressCheckIns to Data Model

### 5a. `UserDataDocument.swift`

**File:** `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/UserDataDocument.swift`

The main app needs to `import TelocareShared` to use the `StressCheckIn` type.

**Add property** (after `hiddenInterventions` on line 19):
```swift
let stressCheckIns: [StressCheckIn]
```

**Add to CodingKeys** (after `hiddenInterventions` on line 106):
```swift
case stressCheckIns
```

**Add to `init(...)` parameters** (after `hiddenInterventions: [String]` on line 62):
```swift
stressCheckIns: [StressCheckIn] = [],
```

And in the init body:
```swift
self.stressCheckIns = stressCheckIns
```

**Add to `init(from decoder:)` decode** (after line 127):
```swift
stressCheckIns = try container.decodeIfPresent([StressCheckIn].self, forKey: .stressCheckIns) ?? []
```

**Add to `static let empty`** (after `hiddenInterventions: []` on line 41):
```swift
stressCheckIns: [],
```

### 5b. `UserDataPatch.swift`

**File:** `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/UserDataPatch.swift`

**Add property** (after `hiddenInterventions` on line 10):
```swift
let stressCheckIns: [StressCheckIn]?
```

**Add static factory:**
```swift
static func stressCheckIns(_ value: [StressCheckIn]) -> UserDataPatch {
    UserDataPatch(
        experienceFlow: nil,
        dailyCheckIns: nil,
        dailyDoseProgress: nil,
        interventionDoseSettings: nil,
        appleHealthConnections: nil,
        morningStates: nil,
        hiddenInterventions: nil,
        stressCheckIns: value
    )
}
```

**Update all 7 existing factory methods** to add `stressCheckIns: nil` as the last parameter. For example, `experienceFlow(_:)` becomes:

```swift
static func experienceFlow(_ value: ExperienceFlow) -> UserDataPatch {
    UserDataPatch(
        experienceFlow: value,
        dailyCheckIns: nil,
        dailyDoseProgress: nil,
        interventionDoseSettings: nil,
        appleHealthConnections: nil,
        morningStates: nil,
        hiddenInterventions: nil,
        stressCheckIns: nil         // ADD THIS LINE
    )
}
```

Same pattern for all 7: `dailyCheckIns(_:)`, `dailyDoseProgress(_:)`, `interventionDoseSettings(_:)`, `appleHealthConnections(_:)`, `morningStates(_:)`, `hiddenInterventions(_:)`.

---

## Step 6: Sync Widget Data on App Foreground

### 6a. `RootViewModel.swift`

**File:** `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/RootViewModel.swift`

Add `import TelocareShared` at top.

**In `hydrate(session:)` — after `state = .ready` on line 183**, add:

```swift
Task.detached { [userDataRepository] in
    await Self.syncPendingWidgetCheckIns(
        existingCheckIns: document.stressCheckIns,
        repository: userDataRepository
    )
}
```

**Add new private static method:**

```swift
nonisolated private static func syncPendingWidgetCheckIns(
    existingCheckIns: [StressCheckIn],
    repository: UserDataRepository
) async {
    let store = WidgetDataStore()
    let pending = store.pendingCheckIns()
    guard !pending.isEmpty else { return }

    let existingIDs = Set(existingCheckIns.map(\.id))
    let newCheckIns = pending.filter { !existingIDs.contains($0.id) }

    guard !newCheckIns.isEmpty else {
        store.clearPendingCheckIns()
        return
    }

    let merged = existingCheckIns + newCheckIns
    do {
        _ = try await repository.upsertUserDataPatch(.stressCheckIns(merged))
        store.clearPendingCheckIns()
    } catch {
        // Leave pending for next foreground attempt
    }
}
```

**Add public method for foreground sync:**

```swift
func syncWidgetDataIfNeeded() {
    guard case .ready = state,
          let vm = dashboardViewModel else { return }
    // Grab current check-ins from the view model if available,
    // otherwise use empty (the sync will still push widget data)
    Task.detached { [userDataRepository] in
        await Self.syncPendingWidgetCheckIns(
            existingCheckIns: [],
            repository: userDataRepository
        )
    }
}
```

### 6b. App entry point — scenePhase observation

**File:** Find where `TelocareApp` / `@main App` struct lives (likely `TelocareApp.swift` or `ContentView.swift`).

Add:
```swift
@Environment(\.scenePhase) private var scenePhase

// On the WindowGroup or root view:
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        rootViewModel.syncWidgetDataIfNeeded()
    }
}
```

---

## Step 7: Tests

### 7a. `TelocareShared/Tests/StressCheckInTests.swift`

```swift
import Testing
@testable import TelocareShared

@Test func stressCheckInCodableRoundTrip() throws {
    let original = StressCheckIn(
        tensionLevel: 7,
        suggestedInterventionId: "diaphragm_breathing",
        interventionCompleted: true
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(StressCheckIn.self, from: data)
    #expect(decoded == original)
}

@Test func tensionLevelTriggersSuggestion() {
    #expect(!TensionLevel.none.triggersSuggestion)
    #expect(!TensionLevel.mild.triggersSuggestion)
    #expect(!TensionLevel.moderate.triggersSuggestion)
    #expect(TensionLevel.strong.triggersSuggestion)
    #expect(TensionLevel.severe.triggersSuggestion)
}

@Test func interventionSuggestionPickExcludesLastId() {
    let suggestion = InterventionSuggestion.pick(excluding: "diaphragm_breathing")
    #expect(suggestion.interventionId != "diaphragm_breathing")
}

@Test func widgetPhaseCodableRoundTrip() throws {
    let phases: [WidgetPhase] = [
        .picker,
        .suggestion(
            interventionId: "diaphragm_breathing",
            interventionName: "Diaphragm Breathing",
            actionLabel: "Try 10 slow breaths",
            checkInId: "abc-123"
        ),
        .completed(interventionName: "Diaphragm Breathing", checkInId: "abc-123"),
    ]
    for phase in phases {
        let data = try JSONEncoder().encode(phase)
        let decoded = try JSONDecoder().decode(WidgetPhase.self, from: data)
        #expect(decoded == phase)
    }
}
```

### 7b. `TelocareShared/Tests/WidgetDataStoreTests.swift`

```swift
import Testing
@testable import TelocareShared

@Test func appendAndReadCheckIns() {
    let store = WidgetDataStore(defaults: UserDefaults(suiteName: "test-widget-store"))
    store.clearPendingCheckIns()

    let checkIn = StressCheckIn(tensionLevel: 7)
    store.appendCheckIn(checkIn)

    let pending = store.pendingCheckIns()
    #expect(pending.count == 1)
    #expect(pending[0].tensionLevel == 7)
}

@Test func clearPendingCheckIns() {
    let store = WidgetDataStore(defaults: UserDefaults(suiteName: "test-widget-store-2"))
    store.appendCheckIn(StressCheckIn(tensionLevel: 5))
    store.clearPendingCheckIns()
    #expect(store.pendingCheckIns().isEmpty)
}

@Test func widgetPhaseRoundTrip() {
    let store = WidgetDataStore(defaults: UserDefaults(suiteName: "test-widget-store-3"))
    let phase = WidgetPhase.suggestion(
        interventionId: "test",
        interventionName: "Test",
        actionLabel: "Do something",
        checkInId: "id-1"
    )
    store.setWidgetPhase(phase)
    #expect(store.widgetPhase() == phase)
}
```

### 7c. Update `UserDataDocumentDecodingTests.swift`

**File:** `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Tests/UserDataDocumentDecodingTests.swift`

Add tests for:
- Decoding JSON that includes a `stressCheckIns` array → verify entries decode correctly
- Decoding JSON that omits `stressCheckIns` entirely → verify defaults to `[]`

---

## Potential Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Tuist may not support `.appExtension` for WidgetKit cleanly | Check `tuist generate` output early (Step 3). May need `.extensionKitExtension` or custom product type. |
| App Group requires Apple Developer portal setup | With `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM` set, Xcode should auto-register. Verify on first build. |
| Widget reload latency could feel sluggish | Acceptable at ~1-2s. The suggestion view content is useful enough to wait for. |
| Race condition: app reads UserDefaults while widget writes | Low risk — app only syncs on foreground (widget not actively tapped). Could add file coordination later if needed. |
| `StressCheckIn` in TelocareShared but `UserDataDocument` in main app | Main app imports TelocareShared. The type is available to both. |

---

## Verification Checklist

1. `tuist generate` succeeds with all 6 targets (3 existing + 3 new)
2. Build main app — compiles with new `stressCheckIns` field and `TelocareShared` import
3. Build widget extension — compiles independently
4. Add widget to home screen in simulator — picker view renders in medium size with 5 emojis
5. Tap low-stress emoji (😌, 🙂, 😐) — check-in stored in UserDefaults, widget stays on picker
6. Tap high-stress emoji (😣, 😫) — widget reloads to show breathing/relaxation suggestion
7. Tap "Done" checkmark — widget shows "Logged ✓", auto-resets to picker after 5 seconds
8. Tap "Skip" — widget returns to picker without marking intervention done
9. Open main app — pending check-ins sync to Supabase, shared UserDefaults cleared
10. Run `TelocareSharedTests` — all model and data store tests pass
11. Run `TelocareTests` — existing tests pass, new decoding test passes
