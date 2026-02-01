# Skywalker v2: macOS Muse Detector Server

Direct Muse S Athena (MS-03) jaw clench detection via OpenMuse, replacing the Mind Monitor dependency.

## Architecture

```
Muse S Athena (BLE) → OpenMuse (LSL) → v2 Python Server → WebSocket → iOS App (unchanged)
```

## Prerequisites

1. **macOS** with Bluetooth enabled
2. **Python 3.11+**
3. **Muse S Athena** (MS-03) headband
4. Grant Bluetooth permissions to Terminal: System Settings → Privacy & Security → Bluetooth

## Setup

```bash
cd v2/muse-detector

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

## Usage

### Step 1: Start OpenMuse streaming (in a separate terminal)

```bash
# Find your Muse device
OpenMuse find

# Start streaming (use the address from above)
OpenMuse stream --address <muse-address>
```

### Step 2: Run the detector

```bash
# Normal operation (5-second calibration, then detection)
./run.sh

# Or with specific options:
python main.py --calibrate --verbose
python main.py --threshold 2.5    # Lower threshold = more sensitive
python main.py --test             # Simulate events every 5 seconds (no Muse needed)
```

### Step 3: Connect iOS app

The iOS app will auto-discover the server via Bonjour. Same protocol as v1.

## CLI Options

| Option | Description |
|--------|-------------|
| `--calibrate` | Run 5-second calibration (keep jaw relaxed) |
| `--threshold N` | Threshold multiplier (default: 3.0) |
| `--test` | Simulate jaw clench events every 5 seconds |
| `--verbose` | Enable debug logging |

## WebSocket Protocol

Same as v1 for iOS app compatibility:

```json
{"event": "connected", "timestamp": "...", "total_events": 0}
{"event": "jaw_clench", "timestamp": "...", "count": 1}
```

## Troubleshooting

### "No LSL stream found"
- Ensure OpenMuse is streaming in another terminal
- Check that `OpenMuse view` shows EEG data

### "Permission denied" for Bluetooth
- Grant Bluetooth access to Terminal in System Settings

### Detection too sensitive / not sensitive enough
- Adjust `--threshold` (higher = less sensitive, lower = more sensitive)
- Default is 3.0 (mean + 3× std deviation)
