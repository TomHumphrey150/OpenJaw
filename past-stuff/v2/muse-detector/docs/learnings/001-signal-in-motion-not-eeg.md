# Learning 001: Training Signal in Motion Sensors, Not EEG

**Date:** 2026-01-31
**Status:** Investigating

## Discovery

Analysis of training data (`compare_signals.py`) revealed that the jaw clench signal is primarily in motion sensors, not EEG:

| Channel | Clench vs Relax Difference |
|---------|---------------------------|
| gyro_z | **-218%** |
| gyro_y | **+173%** |
| acc_x | -46% |
| acc_y | +28% |
| gyro_x | -13% |
| EEG channels (all) | **< 1%** |

## What This Means

The model learned to detect **head movement patterns** associated with jaw clenching, not actual jaw muscle EMG signals in the EEG.

During training, when the user clenched and held spacebar, they likely moved their head slightly. The model found this was the easiest pattern to distinguish clench from relax.

## Why Live Inference Fails

Live inference shows `prob=0.000` even during clenching because:
1. Head movement patterns during live clenching don't match training patterns
2. The model never learned the actual EMG signal (because it didn't need to)

## Physiology: What Should Happen

### Muse S Electrode Positions
- **TP9, TP10** (temporal): Behind ears, near temporalis muscle
- **AF7, AF8** (frontal): On forehead

### Jaw Clenching Muscles
- **Temporalis**: Temple region, contracts during clenching
- **Masseter**: Jaw muscle, primary clenching muscle

### Expected EMG Artifacts
- TP9 and TP10 should pick up temporalis EMG
- EMG signature: 20-40 Hz (beta band), amplitude 75-400µV
- Should be detectable but Muse is consumer-grade, not clinical EEG

## Why EEG Shows < 1% Difference

Possible reasons:
1. **Consumer-grade hardware**: Muse isn't designed for EMG detection
2. **Electrode placement**: Not optimal for temporalis pickup
3. **Simple statistics miss it**: EMG appears in frequency domain (beta band), not raw amplitude
4. **Need frequency features**: Raw mean/std won't show 20-40 Hz changes

## Hypotheses to Test

### Hypothesis A: EEG has signal, but in frequency domain
- Train on EEG only (exclude ACCGYRO)
- Model might learn frequency patterns even if raw stats look similar

### Hypothesis B: Need to keep head still during training
- Re-collect data with explicit "don't move your head" instruction
- Force model to learn EEG patterns instead of motion

### Hypothesis C: Muse can't reliably detect jaw clench via EEG
- Consumer hardware limitation
- Motion-based detection might be the only viable approach

## Next Steps

1. **Experiment: EEG-only training** - Remove ACCGYRO/OPTICS channels, train on 8 EEG channels only
2. **If that fails**: Re-collect training data with head held still
3. **Document results**: Update this file with findings

## References

- Muse electrode positions: TP9/TP10 temporal, AF7/AF8 frontal
- EMG artifacts in EEG peak at 20-40 Hz (beta band)
- Temporalis muscle is primary source of jaw clench EMG near Muse electrodes
