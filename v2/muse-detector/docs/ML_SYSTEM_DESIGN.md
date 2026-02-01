# ML-Based Jaw Clench Detection System Design

## Overview

This document explains the design decisions behind the ML-based jaw clench detection system that replaces the original threshold-based EMG detection with a trained neural network.

## Problem Statement

### Why Replace Threshold-Based Detection?

The original v2 detector used a signal processing pipeline:
1. Bandpass filter (20-100 Hz) to extract EMG from temporalis muscle
2. Full-wave rectification
3. Envelope extraction (5 Hz lowpass)
4. MVC-calibrated threshold (% of maximum voluntary contraction)

**Issues with this approach:**
- Requires calibration every session (user must clench hard for baseline)
- Threshold is position-dependent (lying down vs sitting produces different EMG)
- Hard to tune - false positives vs missed detections tradeoff
- Ignores potentially useful signals (accelerometer, gyroscope)

### ML Solution Benefits
- **No calibration needed** - model learns from pre-labeled data
- **Position-aware** - accelerometer/gyro data captures head position
- **Data-driven** - model discovers what's predictive instead of hand-engineered rules
- **Adaptable** - can retrain on new data to improve

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ./run.py                              │
│                  (Single Entry Point)                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Check data/raw/     2. Check data/models/   3. Run      │
│     └─ No data?            └─ No model?            detection │
│        → Collect              → Train                        │
│                                                              │
│  Interactive prompts guide the user through the flow         │
└─────────────────────────────────────────────────────────────┘
       │                    │                    │
       ▼                    ▼                    ▼
   data/raw/           data/models/         Real-time
   *.parquet           model.pt             detection
```

## Key Design Decisions

### 1. Single Entry Point

**Decision:** Consolidate all ML operations into `run.py`.

**Rationale:**
- Users don't need to remember separate commands for collect/train/detect
- Interactive flow guides users through the process
- Automatic training when new data is collected
- Existing data is preserved by default (reuse without retraining)

**User Experience:**
```bash
./run.py   # That's it - handles everything
```

### 2. Capture ALL Sensor Streams

**Decision:** Capture all Muse channels, not just TP9/TP10 EEG.

**Rationale:**
- The Muse provides multiple sensor streams at different rates:
  - **EEG (256 Hz)**: TP9, AF7, AF8, TP10 - primary EMG signal source
  - **ACCGYRO (52 Hz)**: ACC_X/Y/Z, GYRO_X/Y/Z - head position and movement
- Accelerometer data captures head position (lying down vs sitting)
- Position affects EMG readings - a model trained on all data can learn position-specific patterns
- **Philosophy:** Let the model discover what's predictive rather than us deciding upfront

**Implementation:**
- `MultiStreamReceiver` connects to EEG and ACCGYRO streams simultaneously
- ACCGYRO is resampled (interpolated) to match EEG timestamps during collection
- 10 channels total: 4 EEG + 6 ACCGYRO

### 3. Spacebar Labeling

**Decision:** User labels data in real-time by holding spacebar during clenching.

**Rationale:**
- Simple binary classification: relaxed (0) vs clenching (1)
- Real-time labeling captures actual user behavior
- No post-hoc annotation needed
- User knows best when they're clenching

**Implementation:**
- `pynput` library monitors keyboard state
- `DataCollector` checks spacebar state for each sample
- Samples saved with binary label in parquet files

### 4. Minimal Preprocessing

**Decision:** Only window/normalize - no feature engineering.

**Rationale:**
- Neural networks can learn features from raw data
- Hand-crafted features (FFT bands, statistical summaries) encode assumptions
- Modern CNNs excel at discovering temporal patterns
- Keeps pipeline simple and debuggable

**What we do:**
- **Windowing**: 1-second windows (256 samples at 256 Hz) with 50% overlap
- **Z-score normalization**: Per-channel, using global statistics from training data
- **Label assignment**: Majority vote per window (>50% positive samples → positive label)

**What we DON'T do:**
- No frequency band extraction
- No envelope calculation
- No statistical features (mean, std, kurtosis, etc.)
- No filtering (model sees raw data)

### 5. 1D CNN Architecture

**Decision:** Use 1D Convolutional Neural Network as the primary architecture.

**Why 1D CNN over other options:**

| Architecture | Pros | Cons |
|--------------|------|------|
| **1D CNN** (chosen) | Fast inference, good at local temporal patterns, easy to train | May miss very long-range dependencies |
| **LSTM/GRU** | Captures long-range dependencies | Slower training and inference, harder to parallelize |
| **Transformer** | State-of-the-art for sequences | Overkill for 1-second windows, high memory |
| **Random Forest** | Fast, interpretable | Requires hand-crafted features |

**Why 1D specifically:**
- Our data is 1D temporal sequences (time × channels)
- 2D CNNs are for images (height × width)
- 1D convolutions slide over the time axis, learning temporal patterns

**Architecture details:**

```
CNN (~1.5M params):
  InputProj(10→64)
  6× [Conv1D → BN → ReLU → Conv1D → BN → ReLU → MaxPool]
  Channels: 64 → 64 → 128 → 128 → 256 → 256
  GlobalAvgPool → Dense(128) → Dense(64) → Dense(1)
```

**Kernel sizes:**
- Larger kernels (7, 5) in early layers to capture broader patterns
- Smaller kernels (3) in deeper layers for fine-grained features
- "Same" padding to preserve temporal resolution

### 6. Session-Stratified Train/Val Split

**Decision:** Split by session, not by random samples.

**Rationale:**
- Random split causes data leakage - adjacent windows share data
- A model could "cheat" by memorizing sample patterns
- Session split ensures model generalizes to new recording sessions

**Implementation:**
- `train_val_split(stratify_by_session=True)` keeps entire sessions together
- Default 80/20 split (e.g., 4 sessions train, 1 session val)

### 7. Class Weighting for Imbalance

**Decision:** Use inverse frequency class weights.

**Rationale:**
- Labels are imbalanced (~15-20% positive in typical sessions)
- Without weighting, model would predict all negative and achieve 80%+ accuracy
- Class weights penalize false negatives more heavily

**Implementation:**
```python
weight_positive = n_samples / (2 * n_positive)
weight_negative = n_samples / (2 * n_negative)
pos_weight = weight_positive / weight_negative
criterion = BCEWithLogitsLoss(pos_weight=pos_weight)
```

### 8. Sliding Window Inference

**Decision:** Buffer streaming data until full window available.

**Rationale:**
- Model expects fixed-size 256-sample windows
- Streaming data arrives in variable-sized chunks
- Need to accumulate and process in sliding fashion

**Implementation:**
- `SlidingWindowBuffer` accumulates samples
- When 256 samples available, extract window and run inference
- Debounce logic prevents rapid-fire detections

### 9. Parquet for Data Storage

**Decision:** Store training data as parquet files.

**Rationale:**
- Columnar format - efficient for ML training patterns
- Compression (snappy) reduces storage
- Fast reads with pandas/pyarrow
- Self-describing schema

**Format:**
```
columns: timestamp, eeg_tp9, eeg_af7, eeg_af8, eeg_tp10,
         acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z,
         label, session_id
```

### 10. Checkpoint with Normalization Stats

**Decision:** Save normalization parameters in model checkpoint.

**Rationale:**
- Inference must use same normalization as training
- Channel means/stds must be preserved
- Self-contained checkpoint for deployment

**Checkpoint contents:**
```python
{
    "model_state_dict": ...,
    "config": {"model_type", "n_channels", "window_size"},
    "channel_means": [10 values],
    "channel_stds": [10 values],
    "best_val_metrics": {...}
}
```

## Data Collection Protocol

### Recommended Sessions

Collect multiple sessions across different conditions:
- **Sitting upright** (baseline position)
- **Lying on back**
- **Lying on left side**
- **Lying on right side**

### During Each Session
- Duration: ~3-5 minutes per session
- Alternate between relaxed and clenching/grinding
- Hold spacebar during ANY jaw muscle activity
- Aim for ~15-20% positive samples

### Why Multiple Positions?
The accelerometer data automatically captures head position. By training on multiple positions, the model learns position-invariant detection while also having access to position context if it helps.

## File Structure

```
v2/muse-detector/
├── ml/
│   ├── __init__.py          # Module exports
│   ├── streams.py           # Multi-stream LSL receiver
│   ├── collect.py           # Data collection with labels
│   ├── preprocess.py        # Windowing, normalization
│   ├── model.py             # CNN/LSTM architectures
│   ├── train.py             # Training pipeline
│   └── inference.py         # Real-time inference engine
├── data/
│   ├── raw/                 # Session parquet files
│   └── models/              # Trained model checkpoints
├── tests/
│   ├── test_preprocess.py   # Preprocessing tests
│   ├── test_model.py        # Model architecture tests
│   └── test_inference.py    # Inference engine tests
└── run.py                   # Single CLI entry point
```

## Usage

### Simple Flow (Recommended)

```bash
./run.py
```

The interactive flow will:
1. Check for existing training data
2. Guide you through data collection if needed
3. Train a model automatically if needed
4. Run detection

### Advanced Options

```bash
# Use specific model (skip interactive flow)
./run.py --model data/models/my_model.pt

# Use threshold-based detection instead of ML
./run.py --threshold-mode

# Adjust ML detection threshold
./run.py --ml-threshold 0.6
```

## Debugging

### Verbose Logging

```bash
# Debug level
./run.py -v

# Trace level (very verbose)
./run.py -vv
```

### Log Output Examples

```
[ml] Buffer filling: 128/256
[ml] Inference: prob=0.234, clenching=False, detection=False
[ml] Inference: prob=0.872, clenching=True, detection=True
[ml] JAW CLENCH #1 (probability=0.872)
[websocket] Broadcast to 1 client(s)
```

### Running Tests

```bash
cd v2/muse-detector
pytest tests/ -v
```

## Performance Considerations

### Inference Speed
- CNN: ~5ms per window on M1 Mac
- Easily supports real-time 256 Hz streaming

### Memory Usage
- CNN: ~2 MB model size
- Buffer memory: ~50 KB for sliding window

### Training Time
- CNN: ~5-10 minutes for 10K windows on CPU
- GPU (if available): 5-10x faster

## Future Improvements

### Potential Enhancements
1. **Data augmentation** - Time shifting, noise injection
2. **Multi-task learning** - Predict intensity, not just binary
3. **Transfer learning** - Pre-train on public EEG datasets
4. **Attention mechanisms** - Highlight important time regions
5. **Calibration fine-tuning** - Personalize with few examples

### Model Iteration
As you collect more data:
1. Run `./run.py` and select "Add more training data"
2. Collect additional sessions
3. Model retrains automatically on all data
4. Detection continues with new model

## References

- Original EMG-based bruxism detection: Mumai/Hackaday project
- OpenMuse LSL streaming: https://github.com/DominiqueMakowski/OpenMuse
- 1D CNN for biosignals: Deep learning for EEG/EMG literature
