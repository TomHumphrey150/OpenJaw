# Hybrid V1+V2 Implementation Notes

## Goal

Use Mind Monitor's raw data streaming to collect training data for v2 while v1 handles detection.

## Mind Monitor OSC Addresses

Mind Monitor can stream these via OSC (we currently only use jaw_clench):

| Address | Data | Rate |
|---------|------|------|
| `/muse/eeg` | Raw EEG (TP9, AF7, AF8, TP10, AUX) | 256 Hz |
| `/muse/acc` | Accelerometer (x, y, z) | ~52 Hz |
| `/muse/gyro` | Gyroscope (x, y, z) | ~52 Hz |
| `/muse/elements/jaw_clench` | Detection event | On detection |

Reference: [Mind Monitor OSC Spec](https://mind-monitor.com/FAQ.php#oscspec)

## Current V1 Architecture

```
Muse → Mind Monitor → OSC /muse/elements/jaw_clench → Relay Server → iOS App
```

The relay server only listens for detection events, ignores raw data.

## Proposed Hybrid Architecture

```
Muse → Mind Monitor → OSC (all addresses) → Relay Server
                                                  │
                                    ┌─────────────┴─────────────┐
                                    │                           │
                              V1 Detector                  Data Logger
                              (jaw_clench)                 (eeg, acc, gyro)
                                    │                           │
                                    ▼                           ▼
                              iOS App/Watch              Parquet Files
                                                        (labeled by v1)
```

## Implementation Changes to v1/relay-server/server.py

### 1. Add OSC Handlers for Raw Data

```python
import numpy as np
from collections import deque
from datetime import datetime
import pyarrow as pa
import pyarrow.parquet as pq

# Buffers for raw data
eeg_buffer = deque(maxlen=256 * 60)  # 60 seconds of EEG
acc_buffer = deque(maxlen=52 * 60)   # 60 seconds of accelerometer
gyro_buffer = deque(maxlen=52 * 60)  # 60 seconds of gyroscope

# Timestamps
eeg_timestamps = deque(maxlen=256 * 60)
acc_timestamps = deque(maxlen=52 * 60)
gyro_timestamps = deque(maxlen=52 * 60)

def eeg_handler(address: str, *args):
    """Handle /muse/eeg - raw EEG samples"""
    # args typically: (tp9, af7, af8, tp10) or (tp9, af7, af8, tp10, aux_r, aux_l)
    eeg_buffer.append(args)
    eeg_timestamps.append(datetime.now().timestamp())

def acc_handler(address: str, *args):
    """Handle /muse/acc - accelerometer"""
    # args: (x, y, z)
    acc_buffer.append(args)
    acc_timestamps.append(datetime.now().timestamp())

def gyro_handler(address: str, *args):
    """Handle /muse/gyro - gyroscope"""
    # args: (x, y, z)
    gyro_buffer.append(args)
    gyro_timestamps.append(datetime.now().timestamp())
```

### 2. Register Handlers

```python
async def init_osc_server():
    dispatcher = Dispatcher()

    # Existing v1 detection
    dispatcher.map("/muse/elements/jaw_clench", jaw_clench_handler)

    # NEW: Raw data for v2 training
    dispatcher.map("/muse/eeg", eeg_handler)
    dispatcher.map("/muse/acc", acc_handler)
    dispatcher.map("/muse/gyro", gyro_handler)

    # ... rest unchanged
```

### 3. Log Windows with V1 Labels

```python
# Track detection state for labeling
last_detection_time = None
LABEL_POSITIVE_WINDOW = 2.0  # seconds around detection to label positive
LABEL_NEGATIVE_MIN_GAP = 30.0  # seconds of no detection before labeling negative

def jaw_clench_handler(address: str, *args):
    global last_detection_time, event_count
    event_count += 1
    last_detection_time = datetime.now().timestamp()

    # Log window around this detection as POSITIVE
    log_training_window(label=1, trigger="v1_detection")

    # ... existing broadcast code

def periodic_negative_logging():
    """Called periodically to log negative examples"""
    if last_detection_time is None:
        return

    time_since_detection = datetime.now().timestamp() - last_detection_time
    if time_since_detection > LABEL_NEGATIVE_MIN_GAP:
        log_training_window(label=0, trigger="extended_relaxed")
```

### 4. Save to Parquet

```python
def log_training_window(label: int, trigger: str):
    """Save current buffer state as a training window"""

    # Convert buffers to arrays
    eeg_data = np.array(list(eeg_buffer))
    acc_data = np.array(list(acc_buffer))
    gyro_data = np.array(list(gyro_buffer))

    # Create record
    record = {
        "timestamp": datetime.now().isoformat(),
        "label": label,
        "trigger": trigger,
        "eeg": eeg_data.tobytes(),
        "acc": acc_data.tobytes(),
        "gyro": gyro_data.tobytes(),
        "eeg_shape": eeg_data.shape,
        "acc_shape": acc_data.shape,
        "gyro_shape": gyro_data.shape,
    }

    # Append to daily parquet file
    save_to_parquet(record)
```

## Mind Monitor Settings

Enable OSC streaming in Mind Monitor:
1. Settings → OSC Stream Target IP → [Mac's IP address]
2. Settings → OSC Stream Port → 5000
3. Ensure EEG, ACC, GYRO streaming are enabled (check Mind Monitor settings)

## Data Format Comparison

### OpenMuse (v2 current)
- EEG: 8 channels (TP9, AF7, AF8, TP10, AUX1-4)
- ACCGYRO: 6 channels (acc_x/y/z, gyro_x/y/z)
- Via LSL streams

### Mind Monitor OSC
- EEG: 4-6 channels (TP9, AF7, AF8, TP10, optional AUX)
- ACC: 3 channels (x, y, z) - separate stream
- GYRO: 3 channels (x, y, z) - separate stream
- Via OSC/UDP

### Alignment Needed
- Interpolate ACC/GYRO to EEG timestamps (same as v2 does)
- May have fewer AUX channels than OpenMuse
- Check exact value ranges/scaling match

## Testing Plan

1. **Verify OSC data arrives** - add debug logging for each handler
2. **Check data format** - print shapes, ranges, verify they make sense
3. **Compare to OpenMuse** - run both, compare values for same sensor
4. **Log a test session** - collect 5 mins, inspect parquet
5. **Train v2 on hybrid data** - see if model works

## Open Questions

1. Does Mind Monitor stream AUX channels? (v2 uses 8 EEG channels)
2. Exact timestamp synchronization between EEG/ACC/GYRO?
3. Value scaling - are units the same as OpenMuse?
4. Does Mind Monitor have signal quality indicators?

## Files to Modify

- `v1/relay-server/server.py` - add handlers and logging
- `v1/relay-server/requirements.txt` - add pyarrow, numpy
- Create `v1/relay-server/data/` directory for parquet files
