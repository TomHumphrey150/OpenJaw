# Muse Athena Parser Traceability

Last updated: 2026-02-23

| Parsed stream | SDK symbol(s) | Adapter/parser path | Test coverage | Units/range expectation |
| --- | --- | --- | --- | --- |
| EEG quality (`isGood`) | `IXNMuseDataPacketTypeIsGood`, `getEegChannelValue(IXNEegEEG1...4)` | `MuseSDKPacketAdapter.adapt(_:)` -> `MusePacketAdapterCore.adapt(_:)` -> `MusePacketParser.parse(dataPacket:)` | `MusePacketParserTests.parsesIsGoodPacketIntoBooleanChannels`, `MuseSDKAdapterDeviceTests.adaptsIsGoodPacketFromSdkFactory` | 4 channels, finite, `>= 0.5` interpreted as `true` |
| Headband fit (`hsiPrecision`) | `IXNMuseDataPacketTypeHsiPrecision`, `getEegChannelValue(IXNEegEEG1...4)` | `MuseSDKPacketAdapter` -> `MusePacketAdapterCore` -> `MusePacketParser` | `MusePacketParserTests.parsesHsiPrecisionPacket`, `MuseSDKAdapterDeviceTests.adaptsHsiPrecisionPacketFromSdkFactory` | 4 channels, finite, lower is better (`1/2` good, `4` poor) |
| Accelerometer | `IXNMuseDataPacketTypeAccelerometer`, `getAccelerometerValue(IXNAccelerometerX/Y/Z)` | `MuseSDKPacketAdapter` -> `MusePacketAdapterCore` -> `MusePacketParser` | `MusePacketParserTests.parsesAccelerometerPacket`, `MuseSDKAdapterDeviceTests.adaptsAccelerometerAndGyroPacketsFromSdkFactory` | 3-axis finite values in `g` |
| Gyroscope | `IXNMuseDataPacketTypeGyro`, `getGyroValue(IXNGyroX/Y/Z)` | `MuseSDKPacketAdapter` -> `MusePacketAdapterCore` -> `MusePacketParser` | `MuseSDKAdapterDeviceTests.adaptsAccelerometerAndGyroPacketsFromSdkFactory` | 3-axis finite values in `deg/s` |
| Optics | `IXNMuseDataPacketTypeOptics`, `getOpticsChannelValue(IXNOpticsOPTICS1..16)` | `MuseSDKPacketAdapter` -> `MusePacketAdapterCore` -> `MusePacketParser` | `MusePacketParserTests.parsesOpticsPacketWithVariableChannelCount`, `MuseSDKAdapterDeviceTests.adaptsOpticsPacketFromSdkFactory` | 1..16 finite channels, microamps |
| Raw EEG (optional) | `IXNMuseDataPacketTypeEeg`, `getEegChannelValue(IXNEegEEG1...4)` | `MuseSDKPacketAdapter` -> `MusePacketAdapterCore` -> `MusePacketParser` | `MusePacketParserTests` (core parsing path shared by other packet families) | 4 finite channels, microvolts |
| Artifacts | `IXNMuseDataPacketTypeArtifacts` listener route to `IXNMuseArtifactPacket` (`headbandOn`, `blink`, `jawClench`) | `MuseSDKDataListenerBridge.receive(_:muse:)` -> `MuseSDKPacketAdapter.adapt(_ artifact:)` -> `MusePacketParser.parse(artifactPacket:)` | `MusePacketParserTests.parsesArtifactPacket` | Boolean flags + finite timestamp |
| Unsupported packets | `IXNMuseDataPacketType*` outside mapped set | `MuseSDKPacketAdapter` maps to `.unsupported`, parser returns `nil` | `MusePacketParserTests.rejectsUnsupportedAndNonFinitePackets`, `MuseSDKAdapterDeviceTests.unsupportedPacketTypeReturnsNilWithoutCrashing` | Ignored by parser |

## Type-safety gate

`MusePacketAdapterCore` dispatches by packet type and only calls the matching typed getter family.

Covered by:
- `MusePacketParserTests.adapterCoreUsesOnlyGetterFamilyForAccelerometerType`
- `MusePacketParserTests.adapterCoreUsesOnlyGetterFamilyForOpticsType`

These tests enforce the SIGABRT-avoidance contract from SDK headers.

## Diagnostics traceability

| Diagnostics artifact | Source path | Writer path | Verification coverage | Notes |
| --- | --- | --- | --- | --- |
| Raw Muse stream (`session.muse`) | `IXNMuseDataPacket` + `IXNMuseArtifactPacket` from `MuseSDKDataListenerBridge` | `MuseDiagnosticsSession.recordDataPacket(_:)` / `recordArtifactPacket(_:)` via `IXNMuseFileWriter` | Device build (`MuseSDKSessionService` path) + manual smoke checklist export step | Binary SDK format for full-fidelity replay/debug |
| Setup raw stream (`setup-segment-*.muse`) | Same packet listeners during connect/calibration | `MuseDiagnosticsSession.ensureSetupSegment(now:)` + rolling 60-second segment writers | Setup export smoke + retention checks | Keeps latest 5-minute setup window for pre-recording debugging |
| Per-second decision trace (`decisions.ndjson`, `type=second`) | `MuseSecondDecision` emitted by `MuseArousalDetector` | `MuseSessionAccumulator.buildSummary(onDecision:)` -> `MuseSDKSessionService.stopRecording` -> `MuseDiagnosticsEventWriter.appendDecision(_:)` | `MuseSessionAccumulatorTests.buildSummaryEmitsPerSecondDecisions`, `MuseDiagnosticsReplayTests.replayingDecisionTraceMatchesSummary` | Contains detector inputs, event decisions, awake evidence |
| Session service events (`decisions.ndjson`, `type=service_event`) | Connection state transitions, connect preset/outcome, SDK errors, recording lifecycle | `MuseDiagnosticsRecorder.recordServiceEvent(_:)` -> `MuseDiagnosticsEventWriter.appendServiceEvent(_:at:)` | UI/device smoke flow + manual diagnostics inspection | Supports timeline debugging outside algorithm-only traces |
| Setup fit snapshots (`decisions.ndjson`, `type=fit_snapshot`) | Rolling setup diagnostics (`MuseLiveDiagnostics`) including readiness blockers and per-sensor states | `MuseSDKSessionService.fitDiagnostics(at:)` -> `MuseDiagnosticsRecorder.recordFitSnapshot(_:at:)` -> `MuseDiagnosticsEventWriter.appendFitSnapshot(_:at:)` | `MuseFitReadinessEvaluatorTests`, setup export smoke | Captures setup-specific fit/debug evidence before recording starts |
| Detection summary (`decisions.ndjson`, `type=summary`) | Final `MuseDetectionSummary` from detector | `MuseDiagnosticsEventWriter.appendSummary(_:)` | `MuseDiagnosticsReplayTests.replayingDecisionTraceMatchesSummary` | Snapshot for parity checks during offline tuning |
| Session manifest (`manifest.json`) | Heuristic constants, app version, session bounds, file list | `MuseDiagnosticsEventWriter.writeManifest(startedAt:endedAt:summary:files:)` | Manual export smoke + contract doc | Schema-versioned metadata for tool compatibility |

## EEG sensor location mapping

From `IXNEeg.h` in the vendored Muse SDK:
- `EEG1`: left ear
- `EEG2`: left forehead
- `EEG3`: right forehead
- `EEG4`: right ear
