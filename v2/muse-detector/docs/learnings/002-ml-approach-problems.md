# Why We're Moving Back to V1 Architecture

## Summary

After extensive work on an ML-based jaw clench detector (v2), we're returning to the v1 threshold-based architecture using Mind Monitor. The ML approach encountered multiple compounding issues that make it impractical for reliable detection.

## Problems Encountered

### 1. OPTICS Channel Variance Issue

**Problem:** OPTICS (PPG/heart rate) channels had extremely low variance during training (std ≈ 0.0008). During live inference, even small fluctuations produced normalized values of 30-40 sigma, causing the model to output extreme logits (1100+) and always predict "clenching".

**Symptoms:**
- Probability always 1.0 during inference
- Raw logits in the thousands
- Normalized values showing 39 sigma deviations

**Fix attempted:** Dropped OPTICS channels entirely, using only EEG (8) + ACCGYRO (6) = 14 channels.

**Result:** Fixed the extreme values, but revealed the next problem.

### 2. Model Always Predicts "Not Clenching"

**Problem:** After fixing OPTICS, the model swung to the opposite extreme - always outputting near-zero probability (0.000) regardless of actual jaw state.

**Symptoms:**
- Raw logits always very negative (-9 to -15)
- Sigmoid output ≈ 0.00001
- No detection even during obvious hard clenches

**Root cause:** Model doesn't generalize from training data to live inference.

### 3. Training Data Doesn't Generalize

**Problem:** The model achieved 86.5% validation accuracy on held-out data from the same session, but completely fails on live data.

**Why this happens:**
- Only one training session ("sitting_upright")
- Training and validation data come from the same session (temporal proximity)
- Model learns session-specific patterns, not generalizable clench signatures
- Subtle differences between "training time" and "inference time" conditions

**What would be needed:**
- Multiple sessions across different days
- Different positions (sitting, lying, standing)
- Different headset placements
- Different times of day
- Possibly different environmental conditions

### 4. Headset Required Just to Retrain

**Problem:** The original code required connecting to the Muse headset even just to retrain the model on existing data.

**Fix:** Added `--train-only` flag and mode selection to allow retraining without headset connection.

**Result:** Fixed, but doesn't solve the fundamental ML issues.

### 5. Data Collection is Tedious and Error-Prone

**Problem:** Collecting labeled training data requires:
- Wearing the headset
- Holding SPACEBAR when clenching (ground truth)
- Maintaining focus for 3-5 minutes per session
- Doing this across multiple positions and conditions

**Issues:**
- Human error in labeling (pressing spacebar late/early)
- Fatigue affects both labeling accuracy and clench patterns
- Need many sessions for generalization
- Each session requires setup time

### 6. The Fundamental ML Challenge

**The core issue:** Jaw clenching detection from EEG is a hard problem because:

1. **Signal is indirect** - We're detecting muscle artifact in EEG, not direct EMG
2. **High individual variance** - Everyone's signal looks different
3. **Position-dependent** - Signal changes with head position
4. **Session-dependent** - Electrode contact varies between sessions
5. **No clean ground truth** - Labeling via spacebar is imperfect

A production ML solution would need:
- Hundreds of sessions from the same person
- Or thousands of sessions across many people
- Professional labeling or better ground truth mechanism
- Extensive hyperparameter tuning
- Possibly a different model architecture entirely

## Why V1 Architecture Works Better

The v1 architecture uses **threshold-based detection with MVC calibration**:

```
Muse → Mind Monitor (iPhone) → Relay Server → iOS App → Watch
```

### Advantages:

1. **Per-session calibration** - Calibrates to YOUR signal RIGHT NOW
   - Phase 1: Establish relaxed baseline
   - Phase 2: Establish your maximum clench
   - Threshold set at % of your personal range

2. **No training data needed** - Works immediately after calibration

3. **Adapts to conditions** - Recalibrate if you change position

4. **Simple, interpretable** - Easy to debug and tune threshold

5. **Mind Monitor handles BLE complexity** - Proven, stable Muse connection

### Why Mind Monitor:

- **Reliable BLE connection** - Mind Monitor has years of development handling Muse Bluetooth quirks
- **OpenMuse is experimental** - We encountered connection issues and stream instability
- **Offloads complexity** - Let a dedicated app handle the hard BLE/streaming part

## Why We Can't Just "Collect More Training Data"

### The Fundamental Contradiction

**The whole point of this project is to STOP clenching.**

Bruxism (teeth grinding/jaw clenching) is harmful. The detector exists to alert when clenching happens so you can consciously relax. Asking someone with bruxism to repeatedly, intentionally clench their jaw to collect training data is:

1. **Counterproductive** - Reinforcing the exact habit we're trying to break
2. **Potentially harmful** - Deliberate clenching can cause jaw pain, headaches, tooth damage
3. **Deeply ironic** - "Clench a lot so we can train a model to tell you to stop clenching"

This isn't like collecting data for a gesture recognizer where you can harmlessly repeat the gesture. Each training clench is the thing we're trying to prevent.

### Other Practical Issues

1. **Time investment** - Each good session is 5+ minutes of focused attention
2. **Diminishing returns** - More data from same conditions doesn't help generalization
3. **Need variety** - Would need dozens of sessions across many conditions
4. **No guarantee of success** - Even with more data, the approach might not work
5. **V1 already works** - Why spend hours on data collection when calibration takes 6 seconds?

## Conclusion

The ML approach was an interesting experiment, but the threshold-based v1 architecture is more practical:

| Aspect | V2 (ML) | V1 (Threshold) |
|--------|---------|----------------|
| Setup time | Hours of data collection | 6 seconds calibration |
| Reliability | Poor generalization | Works consistently |
| Adaptability | Needs retraining | Just recalibrate |
| Complexity | Neural network, normalization bugs | Simple signal processing |
| Dependencies | OpenMuse (experimental) | Mind Monitor (proven) |

**Decision:** Return to v1 architecture. Keep v2 code for reference/future experiments.

## Lessons Learned

1. **Calibration > Training** for personal biometric detection
2. **Consider the data collection burden** - if collecting training data conflicts with the problem you're solving, ML might be the wrong approach
3. **Simpler is often better** for real-time physiological monitoring
4. **Don't underestimate BLE complexity** - use proven tools
5. **Validation accuracy ≠ real-world performance** when train/val come from same session
6. **Ground truth matters** - spacebar labeling introduces noise
7. **Debug incrementally** - the OPTICS bug masked the generalization problem

The most important lesson: **ML requires data, and data collection has a cost.** For bruxism detection, that cost is literally doing the harmful thing you're trying to stop. A 6-second calibration clench is acceptable; hours of deliberate clenching is not.
