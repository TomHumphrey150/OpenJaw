# Data Format Compatibility: v1 (Mind Monitor/OSC) vs v2 (OpenMUSE)

This document compares the data formats between the two Skywalker architectures to evaluate whether v1 training data can bootstrap v2 ML models.

## TL;DR

**The plan:** Use v1 (Mind Monitor) to collect a massive labeled training dataset, then train v2's ML model on that data. This leverages Mind Monitor's built-in jaw clench detection as "free" ground truth labels while building toward an independent v2 system.

**Compatibility:** The underlying data is the same (same Muse electrodes, same sample rates). Main differences are naming conventions and potentially scaling factors. A calibration step may be needed.

## Architecture Overview

| Component | v1 | v2 |
|-----------|----|----|
| Data Source | Mind Monitor iOS app | OpenMUSE Python library |
| Transport | OSC over UDP | LSL (Lab Streaming Layer) |
| Jaw Clench | Pre-computed by Mind Monitor | Must implement ourselves (ML) |
| Relay | MacBook relay server | Direct BLE on Mac/iOS |

## EEG Data Comparison

### Channel Names

| Electrode | v1 (Mind Monitor OSC) | v2 (OpenMUSE LSL) |
|-----------|----------------------|-------------------|
| Left temporal | `tp9` | `EEG_TP9` |
| Left frontal | `af7` | `EEG_AF7` |
| Right frontal | `af8` | `EEG_AF8` |
| Right temporal | `tp10` | `EEG_TP10` |

**Note:** Same physical electrodes, different naming convention. v2 uses uppercase with `EEG_` prefix.

### Sample Rates

Both use **256 Hz** for EEG data.

### Data Format

**v1 OSC Message:**
```
/muse/eeg [tp9_value, af7_value, af8_value, tp10_value]
```

**v1 JSONL Storage:**
```json
{"ts": 1700000000.123, "stream": "eeg", "tp9": 850.5, "af7": 820.3, "af8": 815.7, "tp10": 845.2}
```

**v2 LSL Stream:**
- Stream name: `Muse-EEG (device-id)`
- Channels: `["EEG_TP9", "EEG_AF7", "EEG_AF8", "EEG_TP10"]` (4-channel mode)
- Or: `["EEG_TP9", "EEG_AF7", "EEG_AF8", "EEG_TP10", "AUX_1", "AUX_2", "AUX_3", "AUX_4"]` (8-channel mode)

### Scaling

| Source | Units | Notes |
|--------|-------|-------|
| Mind Monitor | Pre-scaled µV | Already converted to microvolts |
| OpenMUSE | Raw ADC with scale factor | `EEG_SCALE = 1450.0 / 16383.0` (~0.0885 µV/count) |

**Action Required:** Verify whether Mind Monitor applies the same scaling factor or if v1 data needs rescaling for v2 model compatibility.

## Accelerometer/Gyroscope Data

### Channel Names

| Sensor | v1 (OSC) | v2 (OpenMUSE) |
|--------|----------|---------------|
| Accelerometer X | `/muse/acc` args[0] → `x` | `ACC_X` |
| Accelerometer Y | `/muse/acc` args[1] → `y` | `ACC_Y` |
| Accelerometer Z | `/muse/acc` args[2] → `z` | `ACC_Z` |
| Gyroscope X | `/muse/gyro` args[0] → `x` | `GYRO_X` |
| Gyroscope Y | `/muse/gyro` args[1] → `y` | `GYRO_Y` |
| Gyroscope Z | `/muse/gyro` args[2] → `z` | `GYRO_Z` |

### Sample Rate

Both use **52 Hz** for accelerometer/gyroscope data.

### Delivery Mechanism

| v1 | v2 |
|----|-----|
| Two separate OSC messages (`/muse/acc`, `/muse/gyro`) | Single combined `ACCGYRO` stream with 6 channels |

### Scaling

| Source | Accelerometer | Gyroscope |
|--------|--------------|-----------|
| OpenMUSE | `ACC_SCALE = 0.0000610352` | `GYRO_SCALE = -0.0074768` |
| Mind Monitor | Unknown (likely pre-scaled) | Unknown (likely pre-scaled) |

**Action Required:** Capture raw values from both sources and compare to determine if scaling alignment is needed.

## Jaw Clench Labels

### v1 Approach (Mind Monitor)

Mind Monitor performs jaw clench detection internally using its proprietary algorithm and sends events:

```
/muse/elements/jaw_clench [1.0]
```

The relay server logs these as:
```json
{"ts": 1700000000.123, "stream": "jaw_clench", "detected": true}
```

**Characteristics:**
- Binary detection (detected/not detected)
- Unknown algorithm (closed source)
- Unknown sensitivity/threshold settings
- May include debouncing

### v2 Approach (OpenMUSE + ML)

OpenMUSE provides only raw sensor data. Jaw clench detection must be implemented:

1. **Threshold-based:** Bandpass filter (20-100 Hz) + RMS envelope + adaptive threshold
2. **ML-based:** Train CNN/LSTM on labeled examples

v2 data collection uses spacebar hold as ground truth label during collection sessions.

## Parquet Output Schema

### v1 (`convert_to_parquet.py` output)

```
timestamp       float64   # Unix timestamp (from EEG, interpolated for others)
eeg_tp9         float64   # EEG channel values
eeg_af7         float64
eeg_af8         float64
eeg_tp10        float64
acc_x           float64   # Accelerometer (interpolated to EEG timeline)
acc_y           float64
acc_z           float64
gyro_x          float64   # Gyroscope (interpolated to EEG timeline)
gyro_y          float64
gyro_z          float64
label           int64     # 0 = no clench, 1 = clench window
session_id      string    # Session identifier
```

### v2 (ML training data)

Uses similar structure via `ml/collect.py` and `ml/preprocess.py`:
- EEG: 4 channels at 256 Hz
- ACCGYRO: 6 channels at 52 Hz (resampled/interpolated as needed)
- Labels: Binary from spacebar ground truth

## Compatibility Assessment

### What Aligns

| Aspect | Status |
|--------|--------|
| Electrode positions | Same (TP9, AF7, AF8, TP10) |
| EEG sample rate | Same (256 Hz) |
| ACC/GYRO sample rate | Same (52 Hz) |
| Sensor channels | Same underlying hardware |
| Label semantics | Both indicate "jaw clench occurred" |

### What Differs

| Aspect | Difference | Impact |
|--------|------------|--------|
| Channel naming | `tp9` vs `EEG_TP9` | Trivial rename |
| EEG scaling | Unknown if same | May need calibration |
| ACC/GYRO scaling | Unknown if same | May need calibration |
| Label source | Mind Monitor algo vs human spacebar | Label quality/consistency differs |
| Label timing | MM detection latency vs human reaction time | Window alignment may differ |

## The Plan: Use v1 to Bootstrap v2

The primary goal is to leverage v1's simpler architecture (Mind Monitor handles detection) to build a massive training dataset, then use that to train v2's ML model.

### Phase 1: Data Collection via v1

Use the v1 pipeline to collect overnight sessions:
- Mind Monitor → OSC → Relay Server → JSONL files
- Mind Monitor's `/muse/elements/jaw_clench` events serve as ground truth labels
- Collect as many nights as possible to build a large, diverse dataset
- Each session produces a parquet file with EEG, ACC, GYRO, and labels

**Advantages of v1 for collection:**
- No ML training required upfront
- Mind Monitor's detection is "good enough" for labeling
- Simple, reliable pipeline already working
- Can run overnight without intervention

### Phase 2: Train v2 Model on v1 Data

Once sufficient v1 data is collected:
1. Convert all v1 JSONL files to parquet (already implemented)
2. Rename columns to match v2 schema (`tp9` → `EEG_TP9`, etc.)
3. Validate/calibrate scaling if needed (see calibration section below)
4. Train v2 ML model (CNN/LSTM) on the combined dataset
5. Use train/validation/test split from different nights

### Phase 3: Validation Against Known Events

Test the trained v2 model against historical data:
- Run inference on held-out v1 sessions
- Compare v2 predictions against Mind Monitor's original labels
- Metrics: precision, recall, F1, latency

This tells us: **Can v2's ML replicate Mind Monitor's detection?**

### Phase 4: Compare v1 vs v2 in Production

Once v2 model is trained and validated:
- Run both systems in parallel on the same live data
- v1: Mind Monitor detection (baseline)
- v2: OpenMUSE + trained ML model
- Compare detection accuracy, latency, false positive rate

This answers: **Is v2 better, worse, or equivalent to v1?**

### Decision Point

Based on Phase 4 results:
- If v2 ≥ v1: Migrate to v2 (eliminates Mind Monitor dependency)
- If v2 < v1: Continue improving v2 model or stick with v1
- Hybrid option: Use v2 for direct BLE, but keep threshold-based detection as fallback

### Calibration (If Needed)

If model performance is poor, scaling mismatch may be the cause:

1. **Calibration Session:** Record simultaneously with both pipelines
   - v1: Mind Monitor → OSC → relay server
   - v2: OpenMUSE → LSL → separate recorder
   - Same Muse headband, same session

2. **Compare Raw Values:** Plot EEG/ACC/GYRO from both sources
   - If linear relationship: compute scaling factor
   - If non-linear: may need more complex transformation

3. **Apply Correction:** Scale v1 data to match v2 units before training

## Known Issues from v2 Logs

The v2 detector initially failed with:
```
Error reading from stream: picks (['TP9', 'TP10']) could not be interpreted as channel names
```

**Cause:** Code was using v1-style names (`TP9`) instead of OpenMUSE names (`EEG_TP9`).

**Resolution:** The `MultiStreamReceiver` in v2 now correctly uses:
```python
EEG_CHANNELS = ["EEG_TP9", "EEG_AF7", "EEG_AF8", "EEG_TP10"]
ACCGYRO_CHANNELS = ["ACC_X", "ACC_Y", "ACC_Z", "GYRO_X", "GYRO_Y", "GYRO_Z"]
```

## References

- OpenMUSE source: `/docs/OpenMuse/`
- OpenMUSE decode.py: Channel definitions, scaling constants
- v1 server.py: OSC handler implementations
- v1 data_collector.py: JSONL storage format
- v1 convert_to_parquet.py: Parquet schema and interpolation
- v2 ml/streams.py: LSL multi-stream receiver
