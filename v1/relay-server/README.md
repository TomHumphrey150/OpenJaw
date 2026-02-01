# Bruxism Biofeedback Relay Server

Python relay server that receives OSC/UDP messages from Mind Monitor (iPhone 1) and forwards jaw clench events via WebSocket to the iOS app (iPhone 2).

## Architecture

```
Mind Monitor (iPhone 1)  →  OSC/UDP  →  This Server  →  WebSocket  →  iPhone 2 App
```

## Quick Start

### 1. Install Dependencies

```bash
pip3 install -r requirements.txt
```

### 2. Start Server

```bash
# Normal mode (requires Mind Monitor)
./run.sh

# Test mode (simulates events every 5 seconds - no hardware needed)
./run.sh --test
```

The script uses `caffeinate` to prevent your Mac from sleeping during overnight runs.

**Test Mode** is perfect for:
- Testing the iOS app without the Muse headband
- Verifying WebSocket → iPhone → Watch flow
- Debugging the end-to-end system

### 3. Configure Mind Monitor

1. Open Mind Monitor on iPhone 1
2. Go to Settings → OSC Stream
3. Set target IP to your Mac's local IP (e.g., `192.168.1.100`)
4. Set port to `5000`
5. Enable OSC streaming

### 4. Connect iPhone 2 App

Configure the iOS app to connect to:
- WebSocket URL: `ws://<your-mac-ip>:8765`

## Configuration

Edit `config.json` to change ports or logging settings.

**Default Ports:**
- OSC (Mind Monitor → Server): UDP `5000`
- WebSocket (Server → iPhone 2): TCP `8765`

## Logs

Log files are written to `logs/relay_YYYY-MM-DD.log` with both file and console output.

## Testing

### Test OSC Reception (without Mind Monitor)

You can test the OSC listener using Python:

```python
from pythonosc import udp_client

client = udp_client.SimpleUDPClient("127.0.0.1", 5000)
client.send_message("/muse/elements/jaw_clench", 1)
```

### Test WebSocket (without iOS app)

Use `websocat` or a browser console:

```bash
websocat ws://localhost:8765
```

You should see a welcome message with current stats.

## Troubleshooting

**Server won't start:**
- Check if ports 5000 or 8765 are already in use: `lsof -i :5000` and `lsof -i :8765`
- Make sure Python 3.9+ is installed: `python3 --version`

**Mind Monitor not connecting:**
- Verify both devices are on the same WiFi network
- Check Mac's firewall settings (System Preferences → Security & Privacy → Firewall)
- Confirm you're using the Mac's local IP, not 127.0.0.1

**WebSocket clients can't connect:**
- Make sure server is running (check for "WebSocket Server listening" in logs)
- Verify firewall allows incoming connections on port 8765
- Test connection with `websocat` or browser first

**Mac goes to sleep:**
- Run with `./run.sh` (includes caffeinate)
- Check Energy Saver settings (System Preferences → Battery/Energy Saver)
- Make sure Mac is plugged into power

## Development

Run server directly (without caffeinate):
```bash
python3 server.py
```

Enable debug logging (modify `server.py`):
```python
logging.basicConfig(level=logging.DEBUG, ...)
```

## Files

- `server.py` - Main relay server (OSC → WebSocket bridge)
- `requirements.txt` - Python dependencies
- `config.json` - Configuration (ports, logging)
- `run.sh` - Startup script with caffeinate
- `logs/` - Daily log files (git-ignored)

## Next Steps

After testing the relay server:
1. Build the iPhone 2 iOS app (WebSocket client → WatchConnectivity)
2. Build the watchOS app (WatchConnectivity → Haptic)
3. Test end-to-end flow
