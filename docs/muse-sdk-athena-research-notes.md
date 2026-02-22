# Muse SDK + Muse S Athena (MS_03) Planning Notes

Last updated: 2026-02-22 (v3)  
Repository: `/Users/tomhumphrey/src/OpenJaw`  
Prepared by: Codex during planning and repo/SDK exploration

## Incremental Update Log

1. 2026-02-22 (v1)
   - Initial consolidated planning notes from repo + SDK/docs exploration.
2. 2026-02-22 (v2)
   - Added and corrected:
     - `runAsynchronously` packet delivery thread behavior.
     - preset disconnect/reconnect side effect.
     - `removeFromListAfter` default behavior note.
     - static archive platform floor checks (`iOS 15.5`, `iOS Simulator 15.5`).
     - simulator architecture strategy options for Apple Silicon.
     - SDK legal/compliance notes from bundled `README.html` and `LICENSE.html`.
     - sample-app clarification about legacy ExternalAccessory protocol plist key.
3. 2026-02-22 (v3)
   - Added locked implementation decisions from product clarification:
     - simulator strategy, packaging strategy, and session UX scope.
     - wake-day attribution rule with concrete date mapping behavior.
     - historical data migration requirement for sleep-derived keys.
     - license handling, raw-storage scope, and runtime-mode constraints.
     - minimum valid session duration and disclaimer requirements.

## Goal and Scope

The target outcome is to integrate the official Muse SDK (v8.0.5) for Muse S Athena (`MS_03`) into the iOS Telocare app and support overnight microarousal detection, replacing any prior reverse-engineering direction.

This document captures all concrete findings from:

- Local repo inspection.
- Local SDK docs and headers in:
  - `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5`
  - `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/doc`
- SDK sample project inspection (Obj-C and Swift).
- Build and architecture checks on the current development machine.

## Environment Facts

- Current app repo root: `/Users/tomhumphrey/src/OpenJaw`
- iOS app project root: `/Users/tomhumphrey/src/OpenJaw/ios/Telocare`
- Machine architecture: `arm64` (Apple Silicon).
- Existing workspace is present:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare.xcworkspace`
- Current simulator build settings default to `ARCHS = arm64` for iPhone simulator destinations.
- Current local `xcodebuild -showBuildSettings` reports `IPHONEOS_DEPLOYMENT_TARGET = 26.2` in this environment.
  - This appears to be a local/Xcode default in this machine state, not an SDK requirement.
- Current workspace contains local uncommitted iOS changes and planning proceeded against that in-place tree state.

## Existing Telocare Architecture Findings

### App structure and wiring

- Main dependency composition occurs in:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AppContainer.swift`
- Existing service pattern already uses protocol + concrete + mock (good insertion pattern for Muse):
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Health/AppleHealthDoseService.swift`
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Health/HealthKitAppleHealthDoseService.swift`
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Health/MockAppleHealthDoseService.swift`

### Night outcomes already exist in data model

- `UserDataDocument` already includes `nightOutcomes: [NightOutcome]`:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/UserDataDocument.swift`
- `NightOutcome` already has fields needed for Muse-derived output:
  - `nightId`
  - `microArousalCount`
  - `microArousalRatePerHour`
  - `confidence`
  - `totalSleepMinutes`
  - `source`
  - `createdAt`

### Existing UI already renders night outcomes

- Dashboard snapshot builder already consumes `nightOutcomes`:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/DashboardSnapshotBuilder.swift`
- Outcome trends support microarousal metrics:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Features/OutcomeTrendDataBuilder.swift`
- Explore outcomes UI already shows:
  - Night chart
  - "Recent nights"
  - Night detail sheet
  - File: `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Features/ExploreTabShell.swift`

### Persistence gap (critical)

- App persistence is patch/RPC based via:
  - `upsert_user_data_patch`
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/SupabaseUserDataRepository.swift`
- `UserDataPatch` does not currently include `nightOutcomes`.
  - File: `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/UserDataPatch.swift`
- Therefore Muse-generated outcomes cannot currently be persisted through the normal patch path without adding this field.

## Supabase and Migration Findings

- Current migrations:
  - `20260215170532_create_user_data.sql`
  - `20260221182000_backfill_default_graph_if_missing.sql`
  - `20260221190000_upsert_user_data_patch.sql`
  - `20260221213000_create_first_party_content.sql`
  - `20260222165353_remove_stress_widget_rpc.sql`
- `upsert_user_data_patch` performs shallow JSON merge:
  - `data = coalesce(public.user_data.data, '{}'::jsonb) || safe_patch`
- Implication:
  - Adding `nightOutcomes` to `UserDataPatch` is sufficient to replace/update the top-level `nightOutcomes` array atomically in one patch.

## SDK Package Inventory

From `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5`:

- `libmuse_ios_8.0.5` directory is extracted and contains:
  - `Muse.framework`
  - `doc/` doxygen HTML docs
  - `examples/MuseStatsIos`
  - `examples/MuseStatsIosSwift`
  - `scripts/make_xcframework.sh`
- Archive files also present in parent directory:
  - `libmuse_ios_8.0.5.tar.gz`
  - `libmuse_catalyst_8.0.5.tar.gz`
  - `libmuse_macos_8.0.5.tar.gz`
  - plus other platform archives

## SDK API/Behavior Findings (Docs + Headers)

### Discovery and connection lifecycle

- Start scan with `startListening`.
- Stop scan with `stopListening`.
- Docs explicitly state: call `stopListening` before connecting to a previously discovered Muse.
  - `IXNMuseManager.h`

### Callback performance constraints

- Data, connection, and error listeners warn against heavy work in callbacks.
  - `IXNMuseDataListener.h`
  - `IXNMuseConnectionListener.h`
  - `IXNMuseErrorListener.h`

### Connection callback constraint

- Do not call `connect` / `disconnect` directly from connection listener callback.
  - Use a different thread or `runAsynchronously`.
  - `IXNMuseConnectionListener.h`

### Connection states to handle

- States include:
  - `Unknown`
  - `Connecting`
  - `Connected`
  - `Disconnected`
  - `NeedsUpdate`
  - `NeedsLicense`
  - `IXNConnectionState.h`

### Reconnect caveat

- `runAsynchronously` has documented race condition when immediately called after a disconnected event from a different thread.
- Safer pattern:
  - call on same thread as disconnected callback, or
  - call after modest delay (e.g. ~1s).
  - `IXNMuse.h`

### Threading caveat

- `execute` is not thread-safe.
- `runAsynchronously` has threading constraints and reconnect caveat.
- When `runAsynchronously` is used, packet callbacks are delivered on the main thread on iOS.
  - Heavy parsing/feature extraction must be handed off immediately to background processing.
- Doc index emphasizes threading section:
  - `doc/index.html`

### Preset behavior caveat

- Changing preset while connected can disconnect the headband.
- If preset is valid for model, SDK auto-reconnects.
- If preset is invalid for model, headband remains disconnected.
  - `IXNMusePreset.h`

### Discovery list staleness and timeout behavior

- `IXNMuseManagerDEFAULTREMOVEFROMLISTAFTER` is documented as 30 seconds.
- `removeFromListAfter(0)` keeps discovered devices until next `startListening`.
  - `IXNMuseManager.h`

### Packet API safety

- Many typed packet getters throw/crash (`SIGABRT`) if called on wrong packet type.
- Must check `packetType` before calling getter methods.
  - `IXNMuseDataPacket.h`
  - `doc/interface_i_x_n_muse_data_packet.html`

### Data stream specifics relevant to quality

- `IXNMuseDataPacketTypeIsGood`:
  - rolling 1-second quality, emitted every 0.1s.
- `IXNMuseDataPacketTypeHsi`:
  - explicitly noted as not emitted by SDK.
- `IXNMuseDataPacketTypeHsiPrecision`:
  - emitted quality fit indicator.
- `IXNMuseDataPacketTypeArtifacts`:
  - artifact callback path, not a normal data packet payload.
  - `IXNMuseDataPacketType.h`

### MS_03 model and presets

- `IXNMuseModelMs03` exists and maps to Muse S Athena / Muse 2025.
  - `IXNMuseModel.h`
- Muse 2025 presets are in `1021+` range, including EEG-only and EEG+Optics options.
  - `IXNMusePreset.h`

### PPG vs Optics for Muse 2025

- `IXNPpg.h` explicitly notes Muse 2025 uses Optics data for PPG.
- `IXNOptics.h` documents channel mapping and microamp units.

### Licensing API

- `IXNMuse` exposes:
  - `setLicenseData:(NSData *)`
- `IXNMuseConfiguration` exposes:
  - `getLicenseNonce`
- `NeedsLicense` connection state can surface during connect.
- `IXNMuse` also exposes `enableException`.
  - Useful to fail fast during development when listener code throws.
  - Should be disabled in production to avoid avoidable app crashes from callback exceptions.

## SDK Sample App Findings

### Swift sample

- Project: `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIosSwift`
- Uses bridging header:
  - `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIosSwift/MuseStatsIosSwift-Bridging-Header.h`
  - imports `<Muse.h>`
- Links:
  - `Muse.framework`
  - `CoreBluetooth.framework`
- Sets Bluetooth usage key in build settings:
  - `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`

### Objective-C sample

- Project: `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIos`
- Info.plist includes:
  - `NSBluetoothAlwaysUsageDescription`
  - `NSBluetoothPeripheralUsageDescription`
  - `UISupportedExternalAccessoryProtocols` with `com.interaxon.muse`
- Sample flow confirms:
  - register connection + data listeners
  - set preset
  - `runAsynchronously`
  - manage disconnect/listening lifecycle
- Clarification:
  - `UISupportedExternalAccessoryProtocols` appears in Obj-C sample but not Swift sample.
  - `showMusePickerWithCompletion` is deprecated for legacy MU-01 behavior.
  - Do not assume this plist key is required for modern BLE-only MS_03 flow.

## Build and Packaging Findings

### make_xcframework script behavior

- Script path:
  - `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/scripts/make_xcframework.sh`
- Expects tar.gz archives in one directory (e.g. `libmuse_ios_8.0.5.tar.gz` etc).
- Refuses paths containing spaces:
  - explicit guard in script.
- Moves header layout from `Headers/api` to `Headers/Muse/api` during xcframework creation.

### Binary slices in provided iOS framework

- `Muse.framework/Muse` is a universal static archive with:
  - `x86_64` slice
  - `arm64` slice
- Verified platform metadata:
  - `x86_64` sample object platform: `IOSSIMULATOR`
  - `arm64` sample object platform: `IOS`
- There is no `arm64-simulator` slice in this artifact.

### Platform floor in SDK binary

- Sampled object files from the arm64 device slice show:
  - `platform IOS`
  - `minos 15.5`
- Sampled object files from the x86_64 simulator slice show:
  - `platform IOSSIMULATOR`
  - `minos 15.5`
- Practical implication:
  - SDK binary was compiled with iOS/iOS Simulator minimum platform 15.5.

### Apple Silicon simulator implication

- On this machine, simulator defaults to `ARCHS = arm64`.
- If Muse is linked unconditionally for simulator targets, arm64 simulator link issues are likely unless build strategy accounts for missing arm64-sim slice.

### System framework linkage implications

- The static archive contains unresolved symbols for both:
  - CoreBluetooth (`CBCentralManager`, related keys/classes)
  - ExternalAccessory (`EAAccessoryManager`, `EASession`, connect/disconnect notifications)
- If linker errors occur in app integration, explicitly link both frameworks.

### Simulator strategy options (for implementation phase)

1. Force simulator to x86_64 for builds/tests that include Muse linkage.
   - Typical setting shape:
     - `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`
   - Requires Rosetta simulator workflow on Apple Silicon.
2. Avoid linking Muse into simulator builds.
   - Keep simulator path on mock service.
   - Link/import Muse only for device-targeted build path.
3. Produce a vendor package that includes an arm64-simulator slice.
   - Not available in the inspected iOS framework artifact.
   - Requires alternate SDK distribution content.

## Existing iOS Project Build Config Findings

- Tuist project manifest:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Project.swift`
- Currently only external dependency is Supabase package.
- Current Info.plist extension includes HealthKit usage descriptions.
- Current Info.plist extension does not include Bluetooth usage descriptions.
- Existing iOS target uses strict warning-as-error settings.
- Current repo has no existing Muse integration references in app project config:
  - no `SWIFT_OBJC_BRIDGING_HEADER` setting for Muse.
  - no Muse framework linkage entry.
  - no existing CoreBluetooth/ExternalAccessory linkage declarations in `Project.swift`.

## Sleep Attribution Findings

- Current first-party interventions source (`data/interventions.json`) configures `sleep_hours` with:
  - `appleHealthConfig.identifier = sleepAnalysis`
  - `appleHealthConfig.aggregation = sleepAsleepDurationSum`
  - `appleHealthConfig.dayAttribution = previousNightNoonCutoff`
- Current app sync logic writes Apple Health dose progress under the current local date key during refresh:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AppViewModel.swift`
  - This supports wake-day assignment when sleep-derived values are synced in the morning.

## SDK Legal and Compliance Notes

- `README.html` points to official SDK terms and conditions:
  - https://choosemuse.com/legal/sdk-terms-and-conditions-agreement/
- Bundled `LICENSE.html` includes broad contractual constraints and risk disclaimers.
- Key planning-relevant takeaways:
  - Ensure usage stays within granted SDK terms.
  - Muse data is not represented as a medical diagnostic substitute in license text.
  - Product/legal review should happen before launch or external commercialization.

## Test Coverage Findings (Current)

- Unit tests cover:
  - `AppViewModel` patch persistence/revert behavior
  - repository patch encoding/decoding
  - snapshot and trend builders
  - root hydration and persistence flows
- UI tests already validate:
  - auth, guided/explore flow, outcomes morning interactions, graph, inputs, profile
  - files:
    - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/UITests/TelocareUITests.swift`
    - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/UITests/TelocareUIExplorerUITests.swift`
- Accessibility identifier constants are centralized in:
  - `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AccessibilityID.swift`

## Repository Standards Constraints Captured

From repo and iOS agent instructions:

- Strict typing and strict compile-time safety expectations.
- No escape hatches (`any`, casts, ts-ignore analogues in TS scope).
- Warnings as errors.
- Accessibility-first, blind-operable UX required.
- Feature logic should stay out of views.
- Supabase schema changes must be local migration SQL + CLI push workflow.

## Product Decisions Locked (2026-02-22)

### Session and UX scope

- V1 is a manual session MVP in Outcomes tab with explicit text-first controls:
  - scan
  - connect/disconnect
  - start/stop recording
  - save night outcome
- Runtime mode for V1 is foreground-only (app open/active).
- Include an in-app non-diagnostic disclaimer in Muse session UI.
- Require a minimum valid recording duration of at least 2 hours before saving a night outcome.

### Output and persistence scope

- V1 detector output is heuristic-derived nightly aggregate metrics:
  - `microArousalCount`
  - `microArousalRatePerHour`
  - `confidence`
  - `totalSleepMinutes`
- Raw packet storage is out of scope for V1 (in-memory processing only).
- Persist one canonical night outcome per `nightId` (upsert/replace semantics for reruns).
- `UserDataPatch` must include `nightOutcomes` to persist through `upsert_user_data_patch`.

### Night/date attribution rule (final)

- Final product rule: all sleep-derived metrics are assigned to wake day.
  - Example: sleep spanning Saturday night to Sunday morning is stored as Sunday (`2026-02-22`).
- Query window decision: use noon-to-noon style collection for sleep-derived queries to capture full overnight sleep while still assigning to wake day.
- This rule applies to Muse outcomes and existing sleep-derived metrics.

### Historical migration requirement

- Historical sleep-derived data must be migrated to wake-day mapping.
- One-time deterministic migration requirement:
  - shift `nightOutcomes[*].nightId` by +1 day.
  - shift `morningStates[*].nightId` by +1 day.
  - shift sleep-derived day keys (including sleep-duration entries in `dailyDoseProgress`) by +1 day.

### Build, packaging, and licensing decisions

- Packaging decision: vendor Muse SDK binary into repo under iOS vendor path.
- Simulator decision: mock-only simulator path; Muse linkage is device-targeted only.
- License decision: optional config-provided base64 license blob; if missing/invalid, surface `NeedsLicense` state in UI rather than crashing app bootstrap.

## Consolidated Risks and Unknowns

1. **Simulator architecture mismatch risk**
   - Current SDK artifact lacks arm64-simulator slice.
2. **Night outcome persistence gap**
   - `UserDataPatch` currently cannot write `nightOutcomes`.
3. **Algorithm validity risk**
   - SDK gives signal streams; microarousal detection heuristic/algorithm remains app-defined and must be validated.
4. **License/update handling**
   - Must define UX for `NeedsLicense` and `NeedsUpdate`.
5. **Callback workload risk**
   - Must offload heavy processing outside listeners.
6. **Threading/reconnect race risk**
   - Must avoid unsafe reconnect from disconnected callbacks on different thread.
7. **Legal/commercialization risk**
   - SDK license terms and commercialization conditions require explicit review before release.

## Integration Direction Derived from Findings

### Data and persistence direction

- Reuse existing `NightOutcome` model.
- Extend `UserDataPatch` with top-level `nightOutcomes`.
- Persist via existing `upsert_user_data_patch` RPC path.
- Add unit tests for new patch encoding and app persistence flow.

### Service architecture direction

- Follow existing service boundary pattern:
  - protocol
  - real Muse SDK implementation
  - mock implementation for tests/simulator/offline.
- Keep view layers declarative; route hardware/session logic through view model and service boundary.

### UX direction

- Add explicit, text-first session states and actions for blind-operable use:
  - scanning
  - connection status
  - recording
  - saving
  - error states (license/update/disconnect).
- Add accessibility IDs for new controls and state labels.

### SDK usage direction

- Use `IXNMuseManagerIos` scanning flow.
- Stop listening before connect.
- Register connection/data/error listeners.
- Handle `NeedsLicense` and `NeedsUpdate`.
- Register data packet types relevant to signal quality + movement + EEG.
- Keep callback handlers lightweight and forward processing to a safe queue/actor.
- Select preset with explicit model awareness.
  - Avoid mid-session preset changes unless reconnect side effect is intentional.

### Build and runtime direction

- Pick and document one simulator strategy early:
  - x86_64 simulator path, or
  - no-Muse-on-simulator path with mock service.
- Keep hardware integration behind protocol boundary so tests and simulator remain deterministic.

## Assumptions Used During Planning

- This is prototype-phase sensor integration with intention to harden before launch.
- Telocare app remains foreground/open overnight for MVP behavior.
- Nightly outcomes are the initial persisted product artifact; raw packet archiving is explicitly out of scope in V1.
- Reverse engineering/off-book protocol work is no longer in scope now that official SDK access exists.

## Quick Next-Step Checklist (Execution Phase)

1. Add durable vendored SDK location under repo (no-space path) and wire device-targeted linkage only.
2. Implement mock-only simulator behavior for Muse service path.
3. Add required iOS build settings:
   - Bluetooth usage descriptions
   - Muse bridge/import settings
   - any required system framework linkage (CoreBluetooth, ExternalAccessory) for device builds.
4. Add Muse service protocol + real + mock implementations.
5. Extend `AppContainer` / view-model wiring for Muse service injection.
6. Extend `UserDataPatch` to support `nightOutcomes`.
7. Add app logic to upsert nightly outcomes by `nightId` and persist patch.
8. Implement wake-day mapping policy and one-time +1 day migration for historical sleep-derived keys.
9. Add outcomes UI controls/status for manual session MVP with text-first accessibility and non-diagnostic disclaimer.
10. Handle connection states including `NeedsLicense` and `NeedsUpdate`; load optional license config if provided.
11. Add unit tests for patch encoding, view-model persistence/revert behavior, attribution mapping, and migration behavior.
12. Add UI test coverage for new controls/state exposure and accessibility IDs.
13. Verify on physical device with Muse S Athena.
14. Run product/legal pass against SDK terms before launch packaging.

## High-Value Files Reviewed

### Repo files

- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Project.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Tuist/Package.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AppContainer.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AppViewModel.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/RootViewModel.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/DashboardSnapshotBuilder.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/UserDataDocument.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/UserDataPatch.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Data/SupabaseUserDataRepository.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Features/ExploreTabShell.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AccessibilityID.swift`
- `/Users/tomhumphrey/src/OpenJaw/supabase/migrations/20260221190000_upsert_user_data_patch.sql`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Tests/TelocareTests.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Tests/UserDataRepositoryTests.swift`
- `/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Tests/RootViewModelTests.swift`

### SDK docs and headers

- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/doc/index.html`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuse.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseManager.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseDataPacket.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseDataPacketType.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseDataListener.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseConnectionListener.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNConnectionState.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMusePreset.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseModel.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNOptics.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNPpg.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/Muse.framework/Headers/api/IXNMuseConfiguration.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/scripts/make_xcframework.sh`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/README.html`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/LICENSE.html`

### SDK sample files

- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIosSwift/MuseStatsIosSwift/ViewController.swift`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIosSwift/MuseStatsIosSwift-Bridging-Header.h`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIosSwift/MuseStatsIosSwift.xcodeproj/project.pbxproj`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIos/MuseStatsIos/SimpleController.m`
- `/Users/tomhumphrey/Downloads/Muse SDK 8.0.5/libmuse_ios_8.0.5/examples/MuseStatsIos/MuseStatsIos/Info.plist`
