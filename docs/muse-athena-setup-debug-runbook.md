# Muse Athena Setup Debug Runbook

Last updated: 2026-02-23

## Scope

This runbook covers setup-phase troubleshooting when Muse connects but fit readiness never reaches the required threshold.

## Primary triage split

1. Transport branch:
   - Receiving-packets pass rate below 90 percent in last 30 seconds.
   - Any recent disconnect or timeout service event.
2. Contact branch:
   - Good EEG channels (>=3) pass rate below 10 percent.
   - Good HSI channels (>=3) pass rate at or above 40 percent.
   - Quality-gate pass rate below 10 percent.
3. Mixed branch:
   - Contact branch signature plus high transport warnings.

## Contact branch interpretation

If setup shows `connected` transport but contact branch signature:
- connection is working
- electrodes are not producing enough clean EEG-quality seconds
- likely causes are positioning, hair interference, skin dryness, muscle tension/artifact

Recommended user action ladder:
1. Re-seat headband and clear hair from forehead and ear sensors.
2. Relax jaw and forehead, stay still for 20 to 30 seconds.
3. Lightly dampen sensor contact points with clean water.
4. Retry setup and verify rolling pass rates improve.

## Transport branch interpretation

If transport branch signature is present:
- keep phone close to headband
- reduce Bluetooth contention
- retry connection and observe packet continuity
- inspect warning histogram and service events for timeout/disconnect trends

## Evidence to collect

Export setup diagnostics zip and inspect:
- `decisions.ndjson`
  - `fit_snapshot.windowPassRates`
  - `fit_snapshot.artifactRates`
  - `fit_snapshot.setupDiagnosis`
  - `service_event` timeout/disconnect markers
- `dev.tuist.Telocare ... .log`
  - SDK packet warnings and timing anomalies
- `setup-segment-*.muse`
  - raw packet replay for `is_good`, HSI precision, artifact profile

## Fast CLI summary

```bash
npm run muse:diagnostics-summary -- /absolute/path/to/muse-setup-diagnostics-directory
```

The summary includes blocker frequency, per-sensor fail rates, dropped packet histogram, and setup diagnosis input/output values.
