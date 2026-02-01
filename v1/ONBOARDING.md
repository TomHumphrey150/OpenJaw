# Skywalker - Onboarding Guide

Welcome to Skywalker! This document will get you up to speed on how the project works.

## What Is This?

Skywalker is a **sleep bruxism (teeth grinding) biofeedback system**. It detects jaw clenching in real-time using an EEG headband and delivers haptic feedback via Apple Watch to interrupt the grinding behavior.

Think of it as a feedback loop: clench your jaw while sleeping → get a gentle tap on your wrist → stop clenching.

## System Architecture

The system involves multiple devices communicating over a local network:

```
Muse S Athena (EEG Headband)
        │
        │ Bluetooth LE
        ▼
iPhone 1 (Mind Monitor app)
        │
        │ OSC/UDP over WiFi
        ▼
MacBook (Python Relay Server)
        │
        │ WebSocket over WiFi
        ▼
iPhone 2 (Skywalker iOS App)
        │
        │ WatchConnectivity
        ▼
Apple Watch (Skywalker watchOS App)
        │
        ▼
    Haptic Feedback
```

**Why this architecture?**
- Mind Monitor is a third-party app that streams EEG data via OSC protocol
- The relay server bridges OSC to WebSocket (easier to work with on iOS)
- WatchConnectivity is Apple's framework for iPhone↔Watch communication

## Project Structure

```
Skywalker/
├── plan.md                     # Product requirements & technical spec
├── relay-server/               # Python relay server
│   ├── server.py               # Main relay implementation
│   ├── requirements.txt        # Python dependencies
│   ├── config.json             # Configuration
│   └── run.sh                  # Startup script
└── Skywalker/                  # iOS/watchOS Xcode project
    ├── Skywalker.xcodeproj/
    └── Skywalker/
        ├── SkywalkerApp.swift  # App entry point
        ├── ContentView.swift   # Main UI
        ├── Models/             # Data structures
        ├── Services/           # Business logic
        └── Views/              # UI components
```

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Relay Server | Python 3.9+, asyncio, pythonosc, websockets, zeroconf |
| iOS App | Swift, SwiftUI, iOS 15+ |
| watchOS App | Swift, SwiftUI (planned) |
| Build System | Xcode |

## Key Patterns

### 1. Service-Oriented Architecture

The iOS app separates concerns into distinct services:

| Service | Responsibility |
|---------|---------------|
| `WebSocketService` | Connects to relay server, receives jaw clench events |
| `WatchConnectivityService` | Sends haptic triggers to Apple Watch |
| `EventLogger` | Persists events to disk, exports as CSV |
| `ServerDiscoveryService` | Finds relay server via Bonjour/mDNS |

### 2. Observable Pattern (SwiftUI)

Services use the `@Observable` macro for reactive UI updates:

```swift
@Observable @MainActor
class WebSocketService: NSObject {
    var isConnected = false
    var lastEventTime: Date?
    var totalEvents = 0
    // UI automatically updates when these change
}
```

### 3. Protocol-Based Communication

**OSC (Mind Monitor → Relay Server):**
```
/muse/elements/jaw_clench  [1]  // Jaw clench detected
```

**WebSocket JSON (Relay Server → iOS App):**
```json
{
  "event": "jaw_clench",
  "timestamp": "2026-01-31T22:44:46Z",
  "count": 1
}
```

**WatchConnectivity (iOS → Watch):**
```swift
["action": "haptic", "pattern": "single_tap", "timestamp": "..."]
```

> **Note:** WatchConnectivity has some non-obvious behaviors around reachability and message delivery. See the "WatchConnectivity Nuances" section below for important details.

## Data Models

### JawClenchEvent

Represents a single jaw clench detection:

```swift
struct JawClenchEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let count: Int
}
```

### HapticPattern

Available haptic feedback patterns:

```swift
enum HapticPattern: String {
    case singleTap = "single_tap"
    case doubleTap = "double_tap"
    case gentleRamp = "gentle_ramp"
    case customPattern = "custom_pattern"
}
```

### AppSettings

User preferences persisted to UserDefaults:

- `serverIP` - Relay server IP address
- `serverPort` - WebSocket port (default: 8765)
- `hapticPattern` - Which haptic to play

## Data Flow

Here's what happens when you clench your jaw:

1. **Muse headband** detects jaw muscle activity via EEG electrodes
2. **Mind Monitor** processes the signal, sends OSC message to relay server
3. **Relay server** receives OSC, broadcasts WebSocket message to connected clients
4. **iOS app** receives WebSocket message, parses JSON
5. **iOS app** logs the event to disk
6. **iOS app** sends haptic trigger via WatchConnectivity
7. **Apple Watch** receives message, plays haptic feedback

Target latency: < 500ms end-to-end.

## Running the System

### 1. Start the Relay Server

```bash
cd relay-server
./run.sh
```

Or for testing without hardware:

```bash
./run.sh --test  # Simulates jaw clench every 5 seconds
```

The server:
- Listens for OSC on UDP port 5000
- Serves WebSocket on TCP port 8765
- Advertises itself via Bonjour as `_skywalker-relay._tcp`

### 2. Run the iOS App

Open `Skywalker/Skywalker.xcodeproj` in Xcode and run on simulator or device.

The app will:
- Auto-discover the relay server via Bonjour (or use manual IP)
- Connect via WebSocket
- Relay haptic triggers to paired Apple Watch

## Development Phases

| Phase | Status | Description |
|-------|--------|-------------|
| 1. Relay Server | Complete | OSC→WebSocket bridge with test mode |
| 2. iOS App | In Progress | Core data models, services, and views |
| 3. watchOS App | Planned | Haptic playback and basic UI |
| 4. Rich UI | Planned | Configuration and event visualization |
| 5. Stability | Planned | Error handling and edge cases |
| 6. Overnight Testing | Planned | 8-hour validation runs |

## Persistence

**Events** are stored as JSON in the app's Documents folder:
```
Documents/jaw_clench_events.json
```

**Settings** are stored in UserDefaults with keys:
- `serverIP`
- `serverPort`
- `hapticPattern`

## Testing

### Test Mode (Relay Server)

Run with `--test` flag to simulate jaw clench events every 5 seconds:

```bash
./run.sh --test
```

This lets you test the iOS app without the Muse headband.

### Manual Testing Checklist

- [ ] Relay server receives OSC from Mind Monitor
- [ ] iOS app connects to relay server via WebSocket
- [ ] iOS app sends messages to watch via WatchConnectivity
- [ ] Watch plays haptic feedback
- [ ] Haptics work even when watch shows "Not Reachable" (test with wrist lowered)
- [ ] End-to-end latency < 500ms
- [ ] System runs for 8 hours without intervention

> **Important:** Running via Xcode keeps the watch artificially "reachable". For realistic testing, deploy standalone and restart both apps.

## Required Permissions

The iOS app needs:

| Permission | Why |
|------------|-----|
| Local Network | Connect to relay server on local WiFi |
| Background Modes (Audio) | Keep app running overnight |

These are declared in `Info.plist`.

## Common Tasks

### Adding a New Haptic Pattern

1. Add case to `HapticPattern` enum in `Models/HapticPattern.swift`
2. Add display name and description
3. Implement playback in watchOS app (when built)

### Changing Default Settings

Edit `AppSettings.swift` - defaults are defined as computed properties with UserDefaults fallbacks.

### Adding New Event Types

1. Create new model in `Models/`
2. Handle in `WebSocketService.handleMessage()`
3. Add persistence in `EventLogger` if needed

## Architecture Decisions

**Why a relay server instead of direct connection?**
- Mind Monitor only supports OSC protocol
- WebSocket is easier to work with on iOS
- Relay allows multiple clients (future: web dashboard)

**Why WatchConnectivity instead of Bluetooth?**
- Apple's official framework for iPhone↔Watch
- More reliable than raw Bluetooth
- Handles watch sleep states properly

## WatchConnectivity Nuances

Understanding WatchConnectivity behavior is critical for this app:

### The `isReachable` Quirk

Apple's `session.isReachable` property is **stricter than expected**:

| Scenario | `isReachable` | Can still receive messages? |
|----------|---------------|----------------------------|
| Watch screen fully on, app in foreground | `true` | Yes (immediate) |
| Watch screen dimmed (always-on mode) | `false` | Often yes! |
| Watch wrist lowered | `false` | Often yes! |
| Watch app running via extended runtime | `false` | Yes (may be queued) |
| Running via Xcode debugger | `true` (artificially) | Yes |

**Key insight:** `sendMessage()` often succeeds even when `isReachable` reports `false`.

### Our Approach

We always attempt `sendMessage()` first, regardless of `isReachable`:

```swift
// Always try immediate delivery first
session.sendMessage(message, replyHandler: { ... }, errorHandler: { error in
    // Only fall back to queued delivery if sendMessage actually fails
    session.transferUserInfo(message)
})
```

This ensures:
- Immediate haptic delivery when possible (even if `isReachable` is false)
- Queued delivery as fallback (delivered when watch wakes)
- UI buttons are never disabled based on reachability

### Extended Runtime Sessions

The watch app uses `WKExtendedRuntimeSession` with "self-care" type to stay alive overnight:

```swift
extendedRuntimeSession = WKExtendedRuntimeSession()
extendedRuntimeSession?.start()
```

This keeps the app running to receive messages, but does NOT:
- Keep the screen on
- Keep `isReachable` as true
- Prevent the watch from dimming

The app can still receive and process haptics with the screen off.

### Message Delivery Methods

| Method | When Used | Delivery |
|--------|-----------|----------|
| `sendMessage()` | Always attempted first | Immediate (if watch responsive) |
| `transferUserInfo()` | Fallback on failure | Queued, delivered when watch wakes |

### Testing Gotcha

**Running via Xcode artificially keeps the watch "reachable"**. To test real-world behavior:
1. Deploy to physical devices (not via debugger)
2. Force quit both iPhone and Watch apps
3. Restart both apps manually
4. Lower your wrist / let screen dim
5. Then test haptic delivery

**Why SwiftUI?**
- Declarative UI is cleaner for state-driven apps
- Better integration with `@Observable` pattern
- Modern Apple development direction

## Useful Files to Read

| File | What You'll Learn |
|------|-------------------|
| `plan.md` | Full product requirements and technical spec |
| `relay-server/server.py` | How OSC/WebSocket bridging works |
| `Skywalker/Services/WebSocketService.swift` | iOS WebSocket implementation |
| `Skywalker/Services/WatchConnectivityService.swift` | iPhone↔Watch communication |
| `Skywalker/ContentView.swift` | Main app UI and state management |

## Getting Help

- Check `plan.md` for detailed requirements
- Relay server has its own `README.md`
- Look at existing code patterns before implementing new features
