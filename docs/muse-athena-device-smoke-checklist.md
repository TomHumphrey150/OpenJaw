# Muse S Athena (MS-03) Device Smoke Checklist

Last updated: 2026-02-23

## Scope

This checklist validates the v1 real-device path for Muse S Athena parsing and session output.

## Preconditions

- iPhone physical device build (not simulator).
- Muse S Athena (`MS-03`) charged and powered on.
- Telocare built from current branch with vendored Muse SDK.
- Optional: `MUSE_LICENSE_BASE64` present in local secrets.

## Pass/Fail Template

- Run date:
- iPhone model + iOS version:
- Muse model printed on band:
- Muse firmware version:
- License configured (`yes/no`):
- Result (`pass/fail`):
- Notes:

## Steps

1. Install app on iPhone and launch.
2. Navigate to Outcomes tab and locate the Muse session section.
3. Confirm text-first controls are present:
- scan
- connect
- disconnect
- start recording
- stop recording
- save night outcome
- export setup diagnostics
- export diagnostics
4. Tap scan.
5. Verify MS-03 appears and connection status changes to discovered.
6. Tap connect.
7. Verify connection transitions to connected.
8. If first attempt fails and second succeeds, confirm fallback behavior (1031 -> 1021) still reaches connected.
9. Tap start recording and verify full-screen fit calibration opens.
10. In fit calibration, verify text-first status is present:
- live status summary
- signal confidence
- awake likelihood (provisional)
- headband-on coverage
- quality-gate coverage
- primary readiness blocker text
- readiness check list with PASS/FAIL text
- per-sensor status rows for EEG1..EEG4
- ready streak `x/20`
11. In fit calibration, tap `Export setup diagnostics (full zip)` and verify share sheet opens with:
- `setup-segment-*.muse` (one or more files)
- `decisions.ndjson`
- `manifest.json`
- at least one diagnostics log file
12. Verify fit calibration actions:
- `Start recording (fit ready)` disabled until ready streak reaches 20
- `Start anyway (low reliability)` enabled while not ready
13. For smoke, use `Start anyway (low reliability)` and keep app in foreground for at least 2 minutes.
14. While recording, confirm no crashes and connection/recording status text updates.
15. Stop recording.
16. Verify summary text includes:
- microarousal count/rate
- signal confidence
- awake likelihood (provisional)
17. Verify recording reliability text is shown:
- `verified fit`, `limited fit`, or `insufficient signal`
- if started via override, reliability text notes fit override start
18. Verify fit guidance text behavior:
- if fit guidance is `.good`, no fit guidance text is shown
- if fit guidance is `.adjustHeadband` or `.insufficientSignal`, guidance text is shown
19. Verify export button behavior:
- setup export button enabled if latest setup attempt exists
- disabled before stop
- enabled after stop when diagnostics files exist
20. Tap export diagnostics and verify share sheet opens with:
- `session.muse`
- `decisions.ndjson`
- `manifest.json`
- at least one diagnostics log file
21. Confirm save button remains disabled if <2 hours.
22. Repeat with a synthetic long-duration test path (mocked clock or injected summary in test build) and confirm save persists a `nightOutcomes` patch.
23. Confirm saved night appears in Outcomes history.

## Negative-path checks

1. Remove license blob and reconnect.
2. Verify `Needs license` state is surfaced (no crash).
3. If possible with outdated firmware device, verify `Needs device update` path.
4. Try non-MS-03 hardware and confirm unsupported model error text is shown.

## Diagnostics retention check

1. Capture at least one diagnostics export.
2. Capture at least one setup diagnostics export.
3. Advance the test clock by more than 7 days (or use a controlled time provider in debug build) and start a new recording.
4. Verify diagnostics sessions older than 7 days are purged for both setup and recording directories.

## Parsing sanity checks

1. Run device-only adapter tests on device target.
2. Confirm packet families parse without crash:
- `isGood`
- `hsiPrecision`
- `accelerometer`
- `gyro`
- `optics`
3. Confirm unsupported packet types are ignored.

## Sign-off

- Engineer:
- QA reviewer:
- Date:
