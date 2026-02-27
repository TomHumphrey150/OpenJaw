# Muse Athena Diagnostics Contract

Last updated: 2026-02-23

## Scope

This document defines the exported diagnostics bundle for Muse S Athena sessions in Telocare.

The contract is instrumentation-first:
- microarousal counting logic remains unchanged
- awake-likelihood is provisional and diagnostics-only in this phase
- diagnostics are local-only and never uploaded
- fit calibration is a pre-recording quality gate with optional override
- recording reliability classification is computed for UI feedback and not persisted to `nightOutcomes`
- setup calibration diagnostics are captured and exportable separately from recording sessions

## Retention

- Retention window: 7 days.
- Purge behavior: diagnostics sessions older than 7 days are removed when a new diagnostics session is created.
- Setup raw capture uses rolling 60-second `.muse` segments and keeps only the most recent 5 minutes.

## Export bundle

Telocare supports two diagnostics export bundle kinds:
- recording diagnostics (`muse-diagnostics-*.zip`) from completed recordings
- setup diagnostics (`muse-setup-diagnostics-*.zip`) from connect/calibration attempts

Recording bundle files:

| File | Format | Purpose |
| --- | --- | --- |
| `session.muse` | Muse SDK binary stream | Full raw packet/artifact capture for offline debugging |
| `decisions.ndjson` | Newline-delimited JSON | Per-second detector decisions + service events + final summary |
| `manifest.json` | JSON object | Session metadata, constants snapshot, schema version, exported file list |
| diagnostics log file(s) | text log | Business-logic + SDK bridge logs from CocoaLumberjack file logger |

Setup bundle files:

| File | Format | Purpose |
| --- | --- | --- |
| `setup-segment-*.muse` | Muse SDK binary stream | Setup-phase raw packet/artifact capture, rolling 5-minute window |
| `decisions.ndjson` | Newline-delimited JSON | Setup service events + fit snapshots + optional summary |
| `manifest.json` | JSON object | Setup attempt metadata and exported file list |
| diagnostics log file(s) | text log | Business-logic + SDK bridge logs from CocoaLumberjack file logger |

## Fit calibration contract

- Telocare presents a full-screen fit calibration flow before recording starts.
- Ready threshold:
  - receiving live packets
  - `fitGuidance == good`
  - `headbandOnCoverage >= 0.80`
  - `qualityGateCoverage >= 0.60`
  - 20 consecutive good seconds
- Users can bypass readiness with `Start anyway (low reliability)`.
- Fit flow logs include:
  - fit calibration opened/closed
  - ready threshold reached/dropped
  - override start usage
  - start snapshot metrics
- Fit diagnostics include:
  - primary readiness blocker
  - full blocker list in fixed priority order
  - per-sensor (`EEG1...EEG4`) `is_good` and HSI precision status
  - dropped packet type histogram with code + label
  - setup diagnosis classification (`contactOrArtifact`, `contactOrDrySkin`, `transportUnstable`, `mixedContactAndTransport`, `unknown`)
  - rolling 30-second setup pass rates (`receivingPackets`, `headbandCoverage`, `hsiGood3`, `eegGood3`, `qualityGate`)
  - rolling artifact rates (`blinkTrueRate`, `jawClenchTrueRate`)
  - SDK warning histogram (`sdkWarningCounts`) from parsed SDK log warnings (for example negative timestamp packet-type warnings)

## Recording summary additions

`MuseRecordingSummary` includes:

| Field | Type | Notes |
| --- | --- | --- |
| `startedWithFitOverride` | boolean | `true` when recording started via low-reliability override |
| `recordingReliability` | enum | `verifiedFit`, `limitedFit`, or `insufficientSignal` |

## `decisions.ndjson` schema

Each line is a JSON object with:

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | `"second"`, `"service_event"`, `"fit_snapshot"`, or `"summary"` |
| `schemaVersion` | integer | Current value: `2` |
| `timestampISO8601` | string \| null | Used by `service_event` |
| `message` | string \| null | Used by `service_event` |
| `decision` | object \| null | Used by `second` |
| `summary` | object \| null | Used by `summary` |
| `fitSnapshot` | object \| null | Used by `fit_snapshot` |

`type=second` decision payload (`MuseSecondDecision`):

```json
{
  "secondEpoch": 1735689600,
  "headbandOn": true,
  "isGoodChannels": [true, true, true, true],
  "hsiPrecisionChannels": [1, 1, 1, 1],
  "hasQualityInputs": true,
  "hasImuInputs": true,
  "hasOpticsInput": false,
  "qualityGateSatisfied": true,
  "blinkDetected": false,
  "jawClenchDetected": false,
  "motionSpikeDetected": false,
  "fitDisturbanceDetected": false,
  "opticsSpikeDetected": null,
  "eventDetected": false,
  "eventCounted": false,
  "accelerometerMagnitude": 0.04,
  "gyroMagnitude": 2.1,
  "opticsPeakToPeak": null,
  "awakeEvidence": 0.0
}
```

`type=summary` payload (`MuseDiagnosticsSummaryRecord`):

```json
{
  "microArousalCount": 6,
  "validSeconds": 10800,
  "confidence": 0.8,
  "awakeLikelihood": 0.62,
  "headbandOnCoverage": 0.96,
  "qualityGateCoverage": 0.84,
  "fitGuidance": "adjustHeadband"
}
```

`type=fit_snapshot` payload (`MuseDiagnosticsFitSnapshotRecord`):

```json
{
  "elapsedSeconds": 42,
  "signalConfidence": 0.31,
  "awakeLikelihood": 0.88,
  "headbandOnCoverage": 0.76,
  "qualityGateCoverage": 0.21,
  "fitGuidance": "adjustHeadband",
  "rawDataPacketCount": 680,
  "rawArtifactPacketCount": 44,
  "parsedPacketCount": 390,
  "droppedPacketCount": 334,
  "droppedPacketTypes": [
    { "code": 41, "label": "optics", "count": 280 },
    { "code": 2, "label": "eeg", "count": 54 }
  ],
  "fitReadiness": {
    "isReady": false,
    "primaryBlocker": "poorHsiPrecision",
    "blockers": ["poorHsiPrecision", "lowHeadbandCoverage", "lowQualityCoverage"],
    "goodChannelCount": 2,
    "hsiGoodChannelCount": 1
  },
  "sensorStatuses": [
    { "sensor": "eeg1", "isGood": true, "hsiPrecision": 1, "passesIsGood": true, "passesHsi": true },
    { "sensor": "eeg2", "isGood": false, "hsiPrecision": 4, "passesIsGood": false, "passesHsi": false }
  ],
  "lastPacketAgeSeconds": 0.3,
  "setupDiagnosis": "contactOrArtifact",
  "windowPassRates": {
    "receivingPackets": 1.0,
    "headbandCoverage": 0.83,
    "hsiGood3": 0.67,
    "eegGood3": 0.0,
    "qualityGate": 0.0
  },
  "artifactRates": {
    "blinkTrueRate": 0.42,
    "jawClenchTrueRate": 0.76
  },
  "sdkWarningCounts": [
    { "code": 41, "label": "optics", "count": 12 }
  ],
  "latestHeadbandOn": true,
  "latestHasQualityInputs": true
}
```

## `manifest.json` schema

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | integer | Must match NDJSON schema version |
| `capturePhase` | string | `"setup"` or `"recording"` |
| `startedAtISO8601` | string | Session start timestamp |
| `endedAtISO8601` | string | Session end timestamp |
| `appVersion` | string | App version/build string |
| `heuristicConstants` | object | Snapshot of arousal constants used for session |
| `summary` | object \| null | Same shape as NDJSON summary record |
| `files` | string array | Filenames included in exported bundle |

`heuristicConstants` fields:
- `minimumGoodChannels`
- `maximumGoodHsiPrecision`
- `minimumDisturbedChannels`
- `accelerometerMotionThresholdG`
- `gyroMotionThresholdDps`
- `opticsSpikeThresholdMicroamps`
- `refractoryWindowSeconds`
- `maximumConfidence`

## Replay and inspection

Quick summary from exported decision trace:

```bash
npm run muse:diagnostics-summary -- /absolute/path/to/decisions.ndjson
```

Deterministic replay parity test:

```bash
xcodebuild \
  -workspace ios/Telocare/Telocare.xcworkspace \
  -scheme Telocare \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TelocareTests/MuseDiagnosticsReplayTests \
  test
```

## Compatibility policy

- Changes to file shape require a `schemaVersion` increment.
- New fields may be added without breaking existing parsers.
- Existing fields must not be renamed or removed without version bump.
