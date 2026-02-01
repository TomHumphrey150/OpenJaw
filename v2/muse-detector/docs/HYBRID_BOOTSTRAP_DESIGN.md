# Hybrid Bootstrap Architecture: V1 Teaching V2

## Concept

Use v1 (threshold-based) as a "teacher" to automatically label data for v2 (ML). Over time, v2 accumulates enough real-world data to become more sensitive than v1.

```
┌──────────┐    ┌─────────────┐  OSC   ┌─────────────────────────────────┐
│   Muse   │───▶│ Mind Monitor │──────▶│   Mac Relay Server (v1)         │
│ Headband │    │  (iPhone 2)  │       │                                 │
└──────────┘    └─────────────┘       │  ┌─────────────┐ ┌────────────┐ │
                                       │  │ V1 Thresh.  │ │ Data       │ │
                                       │  │ Detector    │ │ Logger     │ │
                                       │  └──────┬──────┘ └─────┬──────┘ │
                                       │         │              │        │
                                       └─────────┼──────────────┼────────┘
                                                 │              │
                                    WebSocket    │              │ Parquet
                                                 ▼              ▼
                                       ┌─────────────┐   ┌─────────────┐
                                       │  iOS App    │   │  Data Lake  │
                                       │  + Watch    │   │  (labeled)  │
                                       └─────────────┘   └─────────────┘
                                                               │
                                                               │ Periodic
                                                               │ retraining
                                                               ▼
                                                        ┌─────────────┐
                                                        │  V2 Model   │
                                                        └─────────────┘
```

**Key insight:** The Mac relay server already receives ALL the raw data via OSC from Mind Monitor. We just add a data logger alongside the v1 detector. No architectural changes to the data flow - just capture what's already passing through.

## How It Works

### Phase 1: V1 Primary (Now)

1. **V1 runs detection** - threshold-based, calibrated per session
2. **Log everything** - all sensor windows + v1's verdict
3. **V1 detection → positive label** - when v1 says "clench", mark window as positive
4. **Extended relaxed → negative label** - when v1 says "relaxed" for N seconds, mark as negative
5. **Alert user** - v1 triggers watch haptic as normal

### Phase 2: V2 Shadow Mode (Later)

1. **V1 still primary** - still triggers alerts
2. **V2 runs in parallel** - makes predictions but doesn't alert
3. **Compare outputs** - log when v1 and v2 agree/disagree
4. **V2 catches what v1 misses?** - if v2 detects and v1 doesn't, that's interesting
5. **Accumulate edge cases** - focus on disagreements for analysis

### Phase 3: V2 Primary (Eventually)

1. **V2 becomes primary** - once accuracy is proven
2. **V1 as backup** - or retired entirely
3. **Continue learning** - v2 can still accumulate data

## Labeling Strategy

### Positive Labels (Clenching)
```
When v1 detects clench:
  - Label the current window as POSITIVE
  - Label the previous 1-2 windows as POSITIVE (onset)
  - High confidence: v1 is accurate when it fires
```

### Negative Labels (Relaxed)
```
When v1 has NOT detected for 30+ seconds:
  - Label current window as NEGATIVE
  - Lower confidence: v1 might be missing subtle clenches
  - But over time, most of these are genuinely relaxed
```

### Uncertain (Don't Label)
```
- 0-30 seconds after a detection (recovery period)
- During calibration
- Poor signal quality periods
```

## Why This Works

### Solves "Can't Collect Data" Problem
- **No deliberate clenching** - labels come from real involuntary clenches
- **Passive collection** - just wear the headset normally
- **Natural variety** - different days, positions, times, moods

### Solves Generalization Problem
- **Real-world data** - not artificial training sessions
- **Diverse conditions** - accumulated over weeks/months
- **Actual use patterns** - the exact scenarios we need to detect

### V1 is a Good Teacher
- **Accurate when it fires** - few false positives
- **Conservative** - misses subtle clenches (false negatives)
- **Perfect for bootstrapping** - high precision, lower recall

### V2 Can Surpass V1
- **More sensitive** - learn subtle patterns v1 misses
- **No calibration needed** - once trained, works immediately
- **Personalized** - trained on YOUR data over time

### Nighttime Use is Perfect
- **Clenches are already happening** - bruxism occurs during sleep
- **Not adding harm** - just labeling existing behavior
- **Rich training data** - prolonged sessions, real involuntary clenches
- **Different conditions** - sleeping positions, sleep stages
- **High volume** - hours of data per night

## Data Schema

```python
@dataclass
class LabeledWindow:
    timestamp: datetime
    session_id: str

    # Sensor data (14 channels x 256 samples)
    eeg_data: np.ndarray      # (256, 8)
    accgyro_data: np.ndarray  # (256, 6)

    # V1 verdict
    v1_detected: bool
    v1_probability: float     # If we add soft labels later

    # Derived label
    label: int                # 1=clench, 0=relaxed, -1=uncertain
    label_confidence: float   # How sure we are of this label

    # Context
    seconds_since_last_detection: float
    calibration_active: bool
    signal_quality: float
```

## Storage Estimate

Per hour of use:
- ~14,400 windows (256 samples @ 256Hz, stride 64)
- ~14 channels × 256 samples × 4 bytes = 14KB per window
- ~200MB per hour uncompressed
- ~50MB per hour with Parquet compression

Per day (4 hours use): ~200MB
Per month: ~6GB
Per year: ~72GB

Manageable, and we can downsample negative examples.

## Implementation Steps

### Step 1: Add Logging to V1
```python
# In v1 relay server, log every window with v1's verdict
def on_window(eeg_data, accgyro_data, timestamp):
    v1_result = threshold_detector.process(eeg_data)

    # Log for v2 training
    logger.log_window(
        timestamp=timestamp,
        eeg_data=eeg_data,
        accgyro_data=accgyro_data,
        v1_detected=v1_result.is_detection,
        seconds_since_detection=get_seconds_since_detection()
    )

    # Normal v1 flow continues
    if v1_result.is_detection:
        send_to_watch()
```

### Step 2: Labeling Script
```python
# Periodic job to assign labels to logged windows
def assign_labels(windows: List[Window]) -> List[LabeledWindow]:
    for w in windows:
        if w.v1_detected:
            w.label = 1  # Positive
            w.label_confidence = 0.95
        elif w.seconds_since_detection > 30:
            w.label = 0  # Negative
            w.label_confidence = 0.80
        else:
            w.label = -1  # Uncertain
            w.label_confidence = 0.0
    return windows
```

### Step 3: Periodic Retraining
```bash
# Weekly cron job
./retrain_v2.py --data-dir /data/labeled --min-hours 10
```

### Step 4: Shadow Mode Comparison
```python
# Run both, compare outputs
v1_result = v1_detector.process(data)
v2_result = v2_model.predict(data)

if v1_result != v2_result:
    log_disagreement(data, v1_result, v2_result)
```

## Success Metrics

### Data Accumulation
- Hours of labeled data
- Number of positive examples
- Diversity (sessions, days, positions)

### Model Quality
- Validation accuracy on held-out sessions
- Agreement rate with v1
- False positive rate in shadow mode

### Sensitivity Improvement
- Does v2 catch clenches v1 misses?
- Human verification of v2-only detections

## Open Questions

1. **How much data is enough?**
   - Start checking v2 quality after 10+ hours
   - Likely need 50+ hours for good generalization

2. **How to verify v2-only detections?**
   - Push notification asking "were you clenching?"
   - Or just trust after enough v1 agreement

3. **When to promote v2 to primary?**
   - When v2 agrees with v1 95%+ of the time
   - And catches additional clenches verified by user

4. **Class imbalance?**
   - Will have many more negative than positive
   - Downsample negatives or use class weights

## Summary

This hybrid approach:
- **Eliminates deliberate clenching** - labels from real involuntary events
- **Accumulates naturally** - just use the system normally
- **Builds over time** - gets better the more you use it
- **Low risk** - v1 always works, v2 is bonus
- **Eventually superior** - v2 learns YOUR patterns across all conditions
