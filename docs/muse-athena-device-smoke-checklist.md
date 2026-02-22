# Muse S Athena (MS-03) Device Smoke Checklist

Last updated: 2026-02-22

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
- export diagnostics
4. Tap scan.
5. Verify MS-03 appears and connection status changes to discovered.
6. Tap connect.
7. Verify connection transitions to connected.
8. If first attempt fails and second succeeds, confirm fallback behavior (1031 -> 1021) still reaches connected.
9. Start recording and keep app in foreground for at least 2 minutes for smoke.
10. While recording, confirm no crashes and connection/recording status text updates.
11. Stop recording.
12. Verify summary text includes:
- microarousal count/rate
- signal confidence
- awake likelihood (provisional)
13. Verify fit guidance text behavior:
- if fit guidance is `.good`, no fit guidance text is shown
- if fit guidance is `.adjustHeadband` or `.insufficientSignal`, guidance text is shown
14. Verify export button behavior:
- disabled before stop
- enabled after stop when diagnostics files exist
15. Tap export diagnostics and verify share sheet opens with:
- `session.muse`
- `decisions.ndjson`
- `manifest.json`
- at least one diagnostics log file
16. Confirm save button remains disabled if <2 hours.
17. Repeat with a synthetic long-duration test path (mocked clock or injected summary in test build) and confirm save persists a `nightOutcomes` patch.
18. Confirm saved night appears in Outcomes history.

## Negative-path checks

1. Remove license blob and reconnect.
2. Verify `Needs license` state is surfaced (no crash).
3. If possible with outdated firmware device, verify `Needs device update` path.
4. Try non-MS-03 hardware and confirm unsupported model error text is shown.

## Diagnostics retention check

1. Capture at least one diagnostics export.
2. Advance the test clock by more than 7 days (or use a controlled time provider in debug build) and start a new recording.
3. Verify diagnostics sessions older than 7 days are purged and only recent sessions remain.

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
