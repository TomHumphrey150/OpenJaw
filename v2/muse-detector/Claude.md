# OpenJaw V2 - Muse Jaw Clench Detector

> **Status: Not Working Yet.** The pure ML approach doesn't generalize from training to live detection. See [learnings/002-ml-approach-problems.md](docs/learnings/002-ml-approach-problems.md) for why. **Use V1 for now.**

**Related docs:** [Main README](../../README.md) | [V1 ONBOARDING](../../v1/ONBOARDING.md) | [Documentation Index](../../docs/DOCUMENTATION_INDEX.md)

---

## Overview

Python-based jaw clench detection from Muse EEG headband. The goal was to replace V1's Mind Monitor + relay server with direct Muse connection via OpenMuse and ML-based detection.

```
Muse Headband → OpenMuse (BLE) → LSL Stream → This Detector → WebSocket → iOS App → Apple Watch
```

### Why It Doesn't Work

The ML model achieves 86% validation accuracy on held-out data from the same session, but completely fails on live data. Key issues:

1. **Training data doesn't generalize** — Model learns session-specific patterns, not jaw clench signatures
2. **Signal is in motion, not EEG** — Model learned head movement patterns, not EMG ([details](docs/learnings/001-signal-in-motion-not-eeg.md))
3. **Data collection is counterproductive** — Collecting training data means deliberately clenching, the exact behavior we're trying to stop

See [002-ml-approach-problems.md](docs/learnings/002-ml-approach-problems.md) for the full post-mortem.

### The Path Forward

The [Hybrid Bootstrap Design](docs/HYBRID_BOOTSTRAP_DESIGN.md) describes a plan to use V1 as a "teacher" to automatically label data for V2. Over time, V2 would accumulate enough real-world data from involuntary sleep clenches to train a working model. This is not yet implemented.

## Quick Start (Single Command)

```bash
cd v2/muse-detector

# 1. Create virtual environment (first time only)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 2. Run everything with a single command
./run.py
```

That's it! The interactive flow handles:
1. Device discovery (or uses saved/provided address)
2. Training data collection (guided prompts)
3. Model training (automatic)
4. Real-time detection with WebSocket server
5. Cleanup on exit

## CLI Options

```bash
./run.py                      # Interactive mode selection
./run.py --train-only         # Retrain model only (no headset needed)
./run.py --address XX:XX      # Use specific Muse address
./run.py --discover           # Force device discovery
./run.py --test               # Test mode (no Muse needed)
./run.py --model path/to.pt   # Skip interactive flow, use specific model
./run.py --threshold-mode     # Use threshold-based detection instead of ML
./run.py --debug              # Debug mode: SPACEBAR = ground truth for comparison
./run.py -v                   # Debug logging
./run.py -vv                  # Trace-level logging
```

### Interactive Flow

When you run `./run.py`, it will first ask what you want to do:

1. **Run live detection** (requires headset)
2. **Retrain model with existing data** (no headset needed)
3. **Collect new training data** (requires headset)

The headset is only connected when needed (for data collection or inference).

**If you have existing data and model:**
- Option 1: Run detection immediately
- Option 2: Retrain without connecting headset
- Option 3: Collect more data, then train and run

**If you have data but no model:**
- Options include training first

**If no data exists:**
- Must collect data first (requires headset)

### discover.py (Standalone Discovery)
```bash
./discover.py              # Interactive discovery, save selection
./discover.py --list       # Just list devices
./discover.py --stream     # Discover, select, and start streaming
```

### main.py (Manual Mode - Requires Separate OpenMuse)
```bash
# Terminal 1: Start OpenMuse streaming
OpenMuse stream --address <muse-address>

# Terminal 2: Run detector
python main.py --verbose
python main.py --threshold 2.5
python main.py --test
```

## Project Structure

```
v2/muse-detector/
├── run.py                     # Single entry point (recommended)
├── run.sh                     # Shell wrapper with caffeinate
├── main.py                    # Manual CLI entry point
├── discover.py                # Muse device discovery
├── config.json                # Configuration
├── requirements.txt           # Dependencies
├── detector/
│   ├── jaw_clench_detector.py # Signal processing pipeline
│   └── filters.py             # Butterworth filter design
├── streaming/
│   └── lsl_receiver.py        # LSL stream connection
├── server/
│   ├── websocket_server.py    # v1-compatible WebSocket
│   └── bonjour_service.py     # mDNS advertisement
├── utils/
│   └── event_logger.py        # JSON event logging
├── ml/                        # ML module
│   ├── streams.py             # Multi-stream LSL receiver
│   ├── collect.py             # Data collection with labels
│   ├── preprocess.py          # Windowing, normalization
│   ├── model.py               # Neural network architectures
│   ├── train.py               # Training pipeline
│   └── inference.py           # Real-time inference
├── data/                      # ML data (gitignored)
│   ├── raw/                   # Training data parquets
│   └── models/                # Trained models
├── tests/                     # Unit tests
├── docs/                      # Documentation
│   └── ML_SYSTEM_DESIGN.md    # ML design decisions
└── logs/                      # Runtime logs (gitignored)
```

## Reference Code

**OpenMuse Repository** (cloned locally):
```
/Users/tomhumphrey/src/Skywalker/docs/OpenMuse/
```

Key files:
- `OpenMuse/cli.py` - CLI command definitions (find, stream, view, record)
- `OpenMuse/muse.py` - `find_muse()` function, BLE device discovery, `MuseS` class
- `OpenMuse/stream.py` - LSL streaming implementation
- `OpenMuse/decode.py` - EEG packet decoding

**Technical Documentation**:
- `docs/technical-docs/muse-v2-plan.md` - Signal processing pipeline, JawClenchDetector design

## Configuration

### config.json
Core detection parameters. Key values:
- `detector.mvc_threshold_percent`: 0.35 (detect at 35% of max clench strength)
- `detector.relaxed_calibration_seconds`: 3 (relaxed jaw baseline duration)
- `detector.clench_calibration_seconds`: 3 (max clench calibration duration)
- `detector.debounce_seconds`: 2.0 (minimum time between detections)
- `websocket.port`: 8765 (same as v1 for iOS compatibility)

### ~/.skywalker/muse_config.json
Saved Muse device address from discovery:
```json
{
  "muse_address": "00:55:DA:B9:FA:20",
  "muse_name": "Muse-AB12"
}
```

## Muse S Athena Pairing

1. Ensure Muse is charged and powered OFF
2. Hold power button 5+ seconds until LED flashes rapidly
3. LED pulses WHITE = pairing mode (2 minute timeout)
4. Run `./run.py --discover` to find and save device

## ML-Based Detection

The detector uses a trained neural network for jaw clench detection. This eliminates calibration and learns position-specific patterns.

**Full design documentation:** [`docs/ML_SYSTEM_DESIGN.md`](docs/ML_SYSTEM_DESIGN.md)

### How It Works

1. **Data Collection:** Hold SPACEBAR when clenching during collection sessions
2. **Training:** 1D CNN learns patterns from all Muse channels (EEG + accelerometer/gyro)
3. **Inference:** Real-time detection at ~1.5M parameter model

### Model Architecture

The CNN model (~1.5M parameters) uses:
- 6 convolutional blocks with increasing filter counts
- Global average pooling for position invariance
- Dense classifier layers

Alternative: LSTM model for capturing longer-range dependencies (slower but may work better for some patterns).

### Data Collection Tips

When collecting training data:
- **Name sessions descriptively:** `sitting_upright`, `lying_back`, `lying_left`, `lying_right`
- **3-5 minutes per session** is recommended
- **Aim for ~15-20% positive samples** (clenching time)
- **Collect multiple positions** for position-aware detection

### Running Tests

```bash
cd v2/muse-detector
pytest tests/ -v
```

## Threshold-Based Detection (Alternative)

For quick testing without ML training, use threshold mode:

```bash
./run.py --threshold-mode
```

This uses MVC (Maximum Voluntary Contraction) calibration:
- Phase 1 (3s): Keep jaw RELAXED
- Phase 2 (3s): CLENCH JAW HARD
- Detection threshold: 35% of your clench strength

## Debug Logging

Use `-v` or `-vv` to see data flow through the pipeline:

```bash
./run.py -v              # Verbose
./run.py -vv             # Very verbose (shows inference details)
```

### Persistent Run Logging

For debugging sessions, use the logging wrapper to save full output:

```bash
./run_with_logging.sh -vv    # Saves to logs/runs/YYYYMMDD_HHMMSS/
```

Then analyze runs:

```bash
./analyze_run.py             # Analyze most recent run
./analyze_run.py --list      # List all runs
./analyze_run.py 20260131_180000  # Analyze specific run
```

### Debug Changelog

`logs/CHANGELOG.md` tracks bugs and fixes with timestamps. Use this to understand
which issues were present during a particular inference run.

### Ground Truth Debug Mode

Run with `--debug` to enable spacebar ground truth during inference:

```bash
./run_with_logging.sh --debug -vv
```

Hold SPACEBAR when actually clenching. Output shows:
```
[ml] Inference: prob=0.850, pred=True, actual=True [OK]
[ml] Inference: prob=0.020, pred=False, actual=True [MISMATCH]
```

The analyze script summarizes accuracy:
```
GROUND TRUTH ANALYSIS (spacebar = actual clench):
  Total with ground truth: 150
  Matches (OK): 140
  Mismatches: 10
    False negatives (clenching but pred=False): 8
    False positives (relaxed but pred=True): 2
  Accuracy: 93.3%
```

### Model Sanity Check

Verify model works on training data:

```bash
python debug_model.py
```

This tests both "training" and "inference" normalization methods to catch mismatches.

```
2024-01-31 10:15:01 DEBUG [discovery] Scanning for 10 seconds...
2024-01-31 10:15:08 DEBUG [discovery] Found: Muse-AB12 (00:55:DA:B9:FA:20)
2024-01-31 10:15:08 INFO  [run] Using saved device: Muse-AB12 (00:55:DA:B9:FA:20)
2024-01-31 10:15:10 DEBUG [lsl] Found stream: Muse-EEG (00:55:DA:B9:FA:20), 256 Hz
2024-01-31 10:15:11 INFO  [lsl] Connected to LSL stream
2024-01-31 10:15:18 DEBUG [ml] Inference: prob=0.872, clenching=True, detection=True
2024-01-31 10:15:18 INFO  [ml] JAW CLENCH #1 (probability=0.872)
```

## Troubleshooting

### OpenMuse not found
```bash
pip install git+https://github.com/DominiqueMakowski/OpenMuse.git
```

### No Muse devices found
- Is Muse powered on and in pairing mode (white LED)?
- Is Bluetooth enabled? Check System Settings > Bluetooth
- Terminal needs Bluetooth permission: System Settings > Privacy & Security > Bluetooth

### LSL stream not found
- Check verbose output: `./run.py -v`
- OpenMuse creates streams like "Muse-EEG (XX:XX:XX:...)" - the receiver supports partial matching

### Too many false positives (ML mode)
- Collect more training data with clear clench/relax labels
- Try adjusting threshold: `./run.py --ml-threshold 0.6`
- Ensure you're not pressing spacebar during relaxed periods

### Clenches not detected (ML mode)
- Lower detection threshold: `./run.py --ml-threshold 0.4`
- Collect more training data with stronger clenches
- Add more sessions in different positions

### iOS app not connecting
- Same WiFi network?
- Firewall allowing port 8765?
- Check Bonjour advertisement: `dns-sd -B _skywalker-relay._tcp`

### Watch shows "Not Reachable" but haptics still work
This is expected! See `v1/Skywalker/Claude.md` and `v1/ONBOARDING.md` for detailed WatchConnectivity behavior documentation. Key points:
- `isReachable` returns false when wrist is lowered (even with app running)
- `sendMessage()` often works even when `isReachable` is false
- We always attempt immediate delivery, falling back to queued delivery only on failure

## Testing Without Muse

```bash
# Simulate jaw clench events every 5 seconds
./run.py --test

# Verify iOS app receives events and triggers watch haptic
```

## Dependencies

- OpenMuse: BLE connection and LSL streaming
- mne-lsl: LSL stream receiving
- scipy: Butterworth filter design
- numpy: Signal processing
- websockets: iOS app communication
- zeroconf: Bonjour/mDNS service advertisement
- torch: ML model training and inference
- pandas/pyarrow: Training data storage
- pynput: Keyboard monitoring for data labeling
