# OpenJaw V1 iOS App - Bruxism Biofeedback System

**Related docs:** [Main README](../../README.md) | [ONBOARDING.md](../ONBOARDING.md) | [Relay Server](../relay-server/README.md) | [V1 Plan](../plan.md) | [Documentation Index](../../docs/DOCUMENTATION_INDEX.md)

---

## Project Overview

Two-iPhone architecture for sleep bruxism (teeth grinding) detection and haptic feedback:

```
Muse Headband → iPhone 1 (Mind Monitor) → MacBook (Relay Server) → iPhone 2 (This App) → Apple Watch (Haptic)
```

## Build/Test Commands

**IMPORTANT: Use FlowDeck CLI for all builds (not xcodebuild).**

FlowDeck provides cleaner, more parseable build output than raw xcodebuild.

### FlowDeck Build Commands

```bash
# First, get a simulator UDID (only needed once per session)
flowdeck simulator list

# Build the iOS app
# Note: --workspace (-w) accepts both .xcworkspace and .xcodeproj files
flowdeck build --workspace Skywalker.xcodeproj --scheme Skywalker --simulator '<UDID>' --verbose

# Example with specific simulator (iPhone 16 Pro on iOS 18.2)
flowdeck build -w Skywalker.xcodeproj -s Skywalker -S 'D1F68041-C3EC-477A-856B-52E46548D6EB' --verbose
```

**Quick reference for common simulators:**
- iPhone 16 Pro: Use UDID from `flowdeck simulator list`
- iPhone 15: Use UDID from `flowdeck simulator list`
- iPhone 14: Use UDID from `flowdeck simulator list`

### Running the App

```bash
# Build and run on simulator
flowdeck run --workspace Skywalker.xcodeproj --scheme Skywalker --simulator '<UDID>'

# Shorthand version
flowdeck run -w Skywalker.xcodeproj -s Skywalker -S '<UDID>'

# Stop the app
flowdeck stop --bundle-id com.yourname.Skywalker
```

### Testing

```bash
# Run unit tests
xcodebuild test -scheme SkywalkerTests -project Skywalker.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run UI tests
xcodebuild test -scheme SkywalkerUITests -project Skywalker.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Project Structure

```
Skywalker/
├── Models/
│   ├── HapticPattern.swift          # Haptic vibration patterns
│   ├── JawClenchEvent.swift         # Event data model
│   └── AppSettings.swift            # User settings persistence
├── Services/
│   ├── WebSocketService.swift       # Relay server connection
│   ├── WatchConnectivityService.swift # iPhone → Watch communication
│   └── EventLogger.swift            # Event persistence
├── Views/
│   ├── ContentView.swift            # Main UI
│   ├── StatusView.swift             # Connection status display
│   ├── SettingsView.swift           # Server IP & haptic config
│   └── EventHistoryView.swift       # Event timeline
└── SkywalkerApp.swift               # App entry point
```

## Setup Requirements

### 1. Relay Server (Python)

The MacBook relay server must be running:

```bash
cd relay-server
./run.sh
```

This starts the relay server on:
- OSC/UDP port 5000 (receives from Mind Monitor)
- WebSocket port 8765 (sends to iPhone 2)

### 2. Mind Monitor (iPhone 1)

Configure Mind Monitor app:
- OSC Target IP: Your Mac's local IP (e.g., `192.168.1.43`)
- OSC Port: `5000`
- Connect to Muse headband
- Start OSC streaming

### 3. This App (iPhone 2)

In-app settings:
- Server IP: Your Mac's local IP (e.g., `192.168.1.43`)
- Server Port: `8765`
- Tap "Connect to Server"

### 4. Apple Watch

- Pair with iPhone 2
- Install watch app (to be implemented in Phase 3)
- Open watch app to receive haptic triggers

## Development Workflow

### Phase 1: ✅ Relay Server (Complete)
- Python OSC/UDP listener + WebSocket server
- Logs to `relay-server/logs/`
- Tested with Mind Monitor

### Phase 2: 🔨 iOS App (In Progress)
- ✅ Data models (HapticPattern, JawClenchEvent, AppSettings)
- ✅ Services (WebSocketService, WatchConnectivityService, EventLogger)
- ✅ Views (ContentView, StatusView, SettingsView, EventHistoryView)
- 🔲 Build and test on simulator
- 🔲 Test WebSocket connection to relay server

### Phase 3: 🔜 watchOS App (Next)
- WatchConnectivityManager (receive messages from iPhone)
- HapticEngine (play vibration patterns)
- Basic UI with dimmed screen

### Phase 4: 🔜 Rich UI & Configuration
- Event history with export
- Haptic pattern testing
- Detailed connection debugging

### Phase 5: 🔜 Stability & Error Handling
- Auto-reconnect logic
- Network failure recovery
- 8-hour endurance testing

### Phase 6: 🔜 Overnight Validation
- Real sleep testing
- Latency measurement (<500ms target)
- Multi-night reliability

## Troubleshooting

### Build Issues

**Missing dependencies:**
```bash
# The project uses standard iOS frameworks only - no CocoaPods or SPM
# If you see import errors, check that all .swift files are added to the Xcode project
```

**FlowDeck errors:**
```bash
# Check FlowDeck license
flowdeck license

# List available simulators
flowdeck simulator list

# Clean build (auto-detects project/workspace)
flowdeck clean --scheme Skywalker
```

### Runtime Issues

**WebSocket not connecting:**
1. Verify relay server is running: `cd relay-server && ./run.sh`
2. Check Mac's local IP: `ifconfig | grep "inet "`
3. Ensure iPhone and Mac are on same WiFi network
4. Check Mac firewall settings (System Preferences → Security & Privacy → Firewall)

**Watch shows "Not Reachable" but haptics still work:**

This is expected behavior! Apple's `isReachable` property is stricter than you'd expect:
- Returns `false` when wrist is lowered (even if watch screen is in always-on dim mode)
- Returns `false` when watch display is not fully active
- Returns `false` even with extended runtime keeping the app alive

**Key insight:** `sendMessage()` often succeeds even when `isReachable` is false. We always attempt `sendMessage()` first and only fall back to `transferUserInfo` (queued delivery) if it actually fails.

The "Test Haptic" button is always enabled regardless of reachability status.

**Watch truly not receiving haptics:**
1. Verify watch is paired with iPhone 2 (not iPhone 1)
2. Force quit both watch and iPhone apps, then restart both
3. Check Bluetooth is enabled on both devices
4. Ensure watch is on wrist and unlocked
5. Note: Running via Xcode keeps the watch artificially "reachable" - real-world testing requires standalone deployment

**Relay server crashes:**
```bash
# Check Python dependencies
cd relay-server
python3 -m pip install -r requirements.txt

# Check logs
tail -f relay-server/logs/relay_*.log
```

## Network Setup

All devices must be on the same WiFi network:

| Device | IP (example) | Port | Role |
|--------|--------------|------|------|
| MacBook | 192.168.1.43 | 5000 (OSC), 8765 (WS) | Relay Server |
| iPhone 1 | 192.168.1.50 | - | Mind Monitor |
| iPhone 2 | 192.168.1.51 | - | This App |
| Apple Watch | (via iPhone 2 BLE) | - | Haptic Output |

## Required Capabilities (Info.plist)

The following capabilities must be enabled in Xcode:

- **Local Network**: Required for WebSocket connection to relay server
- **Background Modes → Audio**: Keeps app alive in foreground during overnight use
- **WatchConnectivity**: Communication with Apple Watch

## Testing Checklist

- [ ] Relay server receives OSC from Mind Monitor
- [ ] Relay server logs jaw clench events
- [ ] iOS app connects to relay server via WebSocket
- [ ] iOS app receives jaw clench events
- [ ] iOS app sends messages to watch via WatchConnectivity
- [ ] Watch plays haptic feedback
- [ ] End-to-end latency < 500ms
- [ ] System runs for 8 hours without intervention
- [ ] Event logging and history export work
- [ ] Settings persistence works across app restarts

## Next Immediate Tasks

1. ✅ Mark ContentView todo as complete
2. 🔨 Build iOS app with FlowDeck
3. 🔨 Fix any compilation errors
4. 🔨 Test WebSocket connection to relay server
5. 🔜 Add watchOS target to project
6. 🔜 Implement watch app components
7. 🔜 Test end-to-end flow

## Related Files

- [`../plan.md`](../plan.md) — Original requirements document
- [`../relay-server/README.md`](../relay-server/README.md) — Relay server documentation
- [`../ONBOARDING.md`](../ONBOARDING.md) — Comprehensive onboarding guide
