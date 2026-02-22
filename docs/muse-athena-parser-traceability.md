# Muse Athena Parser Traceability

Last updated: 2026-02-22

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
