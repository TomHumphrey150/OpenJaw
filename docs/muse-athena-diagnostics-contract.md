# Muse Athena Diagnostics Contract

Last updated: 2026-02-22

## Scope

This document defines the exported diagnostics bundle for Muse S Athena sessions in Telocare.

The contract is instrumentation-first:
- microarousal counting logic remains unchanged
- awake-likelihood is provisional and diagnostics-only in this phase
- diagnostics are local-only and never uploaded

## Retention

- Retention window: 7 days.
- Purge behavior: diagnostics sessions older than 7 days are removed when a new diagnostics session is created.

## Export bundle

Each completed recording can export the following files through the Outcomes card share sheet.

| File | Format | Purpose |
| --- | --- | --- |
| `session.muse` | Muse SDK binary stream | Full raw packet/artifact capture for offline debugging |
| `decisions.ndjson` | Newline-delimited JSON | Per-second detector decisions + service events + final summary |
| `manifest.json` | JSON object | Session metadata, constants snapshot, schema version, exported file list |
| diagnostics log file(s) | text log | Business-logic + SDK bridge logs from CocoaLumberjack file logger |

## `decisions.ndjson` schema

Each line is a JSON object with:

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | `"second"`, `"service_event"`, or `"summary"` |
| `schemaVersion` | integer | Current value: `1` |
| `timestampISO8601` | string \| null | Used by `service_event` |
| `message` | string \| null | Used by `service_event` |
| `decision` | object \| null | Used by `second` |
| `summary` | object \| null | Used by `summary` |

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

## `manifest.json` schema

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | integer | Must match NDJSON schema version |
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
