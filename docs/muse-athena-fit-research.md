# Muse Athena Fit Research Dossier

Last updated: 2026-02-23

## Scope

This dossier summarizes fit-related signal quality risks for Muse S Athena and the user guidance required in Telocare.

## Key findings

1. Sensor contact quality is the dominant practical constraint for useful EEG-quality channels in home use.
2. Awake-proxy movement can be high while microarousal counting remains low if quality-gate coverage is poor.
3. Moisture escalation is useful as a fallback, not a first-line step.
4. Microarousal interpretation must remain distinct from generic wakefulness because scored arousals require sleep context.

## Sources and implications

1. Official setup guidance emphasizes placement/contact and allows dampening or gel for hard-fit cases.
   Source: [Muse 2 start guide](https://choosemuse.com/pages/muse-2-start-guide/)
   Product implication: fit guidance must prioritize placement and direct contact checks before recording.

2. Official FAQ guidance calls out dry skin and contact issues, and recommends cleaning sensors and improving contact.
   Source: [InteraXon help mirror](http://nagasm.org/1106/Muse/doc/interaxon_muse_help/InteraXon%20Help%20Center%20-%20What%20if%20I%20cannot%20connect%20my%20Muse%20headband%20to%20my%20application_.html)
   Product implication: include practical cleaning/contact troubleshooting in-app.

3. Muse raw signal streams identify `is_good` and `hsi` as the fit-quality anchors.
   Source: [Muse OSC paths](https://mind-monitor.com/Muse-OSC-Paths/)
   Product implication: calibrate readiness on headband-on plus quality-gate metrics derived from these streams.

4. Home-use Muse dry-EEG research reports low-signal sessions and uses dampening/conductive adjustments in difficult setups.
   Source: [Muse-S home sleep study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12782022/)
   Product implication: moisture escalation steps should be explicit and cautious.

5. Consumer wearable EEG comparison literature reports substantial device quality variability, with Muse quality limits in that evaluation.
   Source: [Consumer wearable EEG quality comparison](https://pmc.ncbi.nlm.nih.gov/articles/PMC11679099/)
   Product implication: expose reliability state in outcomes and avoid overconfidence messaging.

6. Additional dry-electrode sleep literature reinforces practical home-use quality limitations and PSG tradeoffs.
   Source: [Dry EEG sleep staging perspective](https://pmc.ncbi.nlm.nih.gov/articles/PMC11940836/)
   Product implication: keep diagnostics-first tuning loop and exportable traces.

7. AASM-oriented arousal criteria require EEG shift duration and prior sleep context.
   Source: [AASM ISR help](https://isr.aasm.org/helpv5/Main/Signal%20analyzer.html)
   Product implication: keep wake proxy and microarousal scoring as separate metrics.

8. Recent wearable arousal modeling supports multimodal evidence but still shows context/device dependencies.
   Source: [Scientific Reports 2025 arousal detection](https://www.nature.com/articles/s41598-025-27739-7)
   Product implication: continue instrumentation and replay-based calibration.

9. Community threads frequently report side-sensor contact/hair issues and sleep-stage consistency concerns.
   Sources:
   - [Reddit side-sensor thread](https://www.reddit.com/r/Meditation/comments/13r2fbi/muse_2_poor_signal_quality_in_side_sensors/)
   - [Reddit sleep-stage thread](https://www.reddit.com/r/Meditation/comments/1mkjtv7/muse_s_sleep_stage_not_tracking/)
   Product implication: include explicit hair/contact checks and a low-reliability override path.

## Guidance ladder for Telocare

1. Reposition headband and clear hair from sensor contact points.
2. Hold still for 20 to 30 seconds after each adjustment.
3. If still poor, lightly dampen contact points with clean water.
4. If still poor, optional tiny saline/conductive gel amount, then clean sensors post-session.

## Product requirements locked from research

1. Full-screen fit calibration before recording.
2. Ready gate based on streaming + quality thresholds, with continuous streak requirement.
3. Override start path with explicit low-reliability warning.
4. Post-recording reliability classification shown separately from confidence and awake proxy.
