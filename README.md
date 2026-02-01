# OpenJaw

**Sleep bruxism biofeedback system** — detect teeth grinding in real-time and deliver gentle haptic feedback via Apple Watch to interrupt the behavior.

## What is this?

OpenJaw is a biofeedback system for sleep bruxism (teeth grinding). It uses a consumer EEG headband ([Muse S Athena](https://choosemuse.com/products/muse-s-athena)) to detect jaw clenching during sleep, then delivers a gentle vibration through your Apple Watch to interrupt the grinding behavior before it causes damage.

**The goal:** Train your brain to stop grinding over time, rather than just protecting your teeth with a mouth guard.

## Why build this?

Sleep bruxism affects 8-13% of adults and causes:
- Tooth damage and wear
- TMJ disorders and jaw pain
- Headaches and facial pain
- Poor sleep quality

Current treatments (mouth guards, Botox) either just protect teeth or temporarily weaken muscles. Biofeedback is different — it can actually train the unconscious behavior to stop.

Commercial biofeedback devices exist but cost $500-2000+ and use proprietary hardware. OpenJaw uses consumer hardware you may already own and is completely open source.

## How it works

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Muse S Athena  │  BLE    │    Detection    │   WiFi  │   iOS + Watch   │
│   (Headband)    │ ──────► │     Server      │ ──────► │     Apps        │
│                 │         │   (Mac/Python)  │         │                 │
└─────────────────┘         └─────────────────┘         └────────┬────────┘
                                                                  │
     Worn during sleep            Detects jaw                     │
     EEG + EMG signals            clenching                       ▼
                                                         ┌─────────────────┐
                                                         │  Apple Watch    │
                                                         │                 │
                                                         │   *buzz buzz*   │
                                                         └─────────────────┘

                                                         Gentle haptic wakes
                                                         you just enough to
                                                         stop grinding
```

The Muse headband's temporal electrodes (TP9/TP10) sit directly over the temporalis muscle — the main jaw-closing muscle. When you clench, EMG signals from the muscle create distinctive high-amplitude patterns that we detect and respond to.

---

## Project Structure

OpenJaw has two versions with different architectures:

### V1: Two-iPhone Architecture (Production)

Uses Mind Monitor (a third-party app) for signal acquisition. Requires two iPhones.

```
Muse Headband ──► iPhone 1 (Mind Monitor) ──► Mac (Relay Server) ──► iPhone 2 (OpenJaw) ──► Apple Watch
                        │                           │                       │
                   Connects to Muse            Receives OSC,           Receives events,
                   via BLE, streams           forwards via             triggers Watch
                   jaw events via OSC          WebSocket               haptics
```

**Components:**
| Component | Location | Platform | Purpose |
|-----------|----------|----------|---------|
| Mind Monitor | App Store ($15) | iOS | Connects to Muse, detects jaw clenches, streams OSC |
| Relay Server | `v1/relay-server/` | macOS/Python | Receives OSC, broadcasts via WebSocket |
| OpenJaw iOS | `v1/Skywalker/` | iOS (Swift) | Receives events, manages Watch, logs history |
| OpenJaw Watch | `v1/Skywalker/` | watchOS (Swift) | Delivers haptic feedback |

**Why two iPhones?** Mind Monitor must stay in the foreground to maintain the Bluetooth connection to the Muse. The second iPhone runs OpenJaw and can do other things (like stay on the nightstand with the screen off).

### V2: Direct Connection Architecture (Experimental)

Bypasses Mind Monitor entirely using [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse) for direct Bluetooth connection.

```
Muse Headband ──► Mac (OpenMuse + Detector) ──► iPhone (OpenJaw) ──► Apple Watch
                        │
                   Direct BLE connection,
                   custom detection algorithm,
                   WebSocket server
```

**Components:**
| Component | Location | Platform | Purpose |
|-----------|----------|----------|---------|
| OpenMuse | External dependency | macOS | Direct BLE connection to Muse, streams via LSL |
| Detector Server | `v2/muse-detector/` | macOS/Python | Custom jaw detection algorithm, WebSocket server |
| OpenJaw iOS | `v1/Skywalker/` | iOS (Swift) | Same app as V1 — protocol compatible |
| OpenJaw Watch | `v1/Skywalker/` | watchOS (Swift) | Same app as V1 |

**Advantages over V1:**
- Only need one iPhone
- No $15 Mind Monitor purchase
- Full control over detection algorithm
- Can tune sensitivity for sleep vs. awake

**Current status:** Experimental. The detection algorithm needs more tuning for sleep use.

---

## Hardware Requirements

### Required
- **Muse S Athena** (MS-03) — the sleep-focused fabric headband (~$500)
- **iPhone** — iOS 15+ for the OpenJaw app
- **Apple Watch** — Series 3+ for haptic feedback
- **Mac** — for running the relay/detection server

### For V1 only
- **Second iPhone** — dedicated to running Mind Monitor
- **Mind Monitor app** — $15 on App Store

---

## Quick Start

### V1 Setup (Recommended for first-time users)

1. **Start the relay server on your Mac:**
   ```bash
   cd v1/relay-server
   pip install -r requirements.txt
   ./run.sh
   ```

2. **Configure Mind Monitor on iPhone 1:**
   - Install Mind Monitor from App Store
   - Connect to your Muse headband
   - Settings → OSC Stream Target IP: `<your Mac's IP>`
   - Settings → OSC Stream Port: `5000`
   - Start streaming (tap the OSC icon)

3. **Install OpenJaw on iPhone 2:**
   - Open `v1/Skywalker/Skywalker.xcodeproj` in Xcode
   - Build and run on your iPhone
   - The app will auto-discover the relay server

4. **Install Watch app:**
   - Select the Watch target in Xcode
   - Build and run on your paired Apple Watch

5. **Test it:**
   - Clench your jaw while wearing the Muse
   - Your Watch should vibrate within ~500ms

### V2 Setup (Experimental)

1. **Install OpenMuse:**
   ```bash
   pip install openmuse
   ```

2. **Start OpenMuse streaming:**
   ```bash
   OpenMuse find          # Find your Muse
   OpenMuse stream --address <muse-address>
   ```

3. **Start the detector server:**
   ```bash
   cd v2/muse-detector
   pip install -r requirements.txt
   ./run.sh
   ```

4. **Connect the iOS app** (same as V1 step 3-4)

---

## The iOS App

Beyond biofeedback, the OpenJaw iOS app includes:

### Daily Habits
Evidence-based interventions for managing bruxism:
- **Daytime awareness reminders** — periodic prompts to check jaw position
- **Lifestyle tracking** — caffeine, alcohol, stress management
- **Exercises** — jaw stretches, massage techniques

### Progress Tracking
- Nightly event counts and trends
- Week-over-week comparisons
- Integration with HealthKit sleep data

### Notification Grouping
Combine multiple reminder habits into single notifications to reduce interruption fatigue.

---

## Network Architecture

All devices must be on the same WiFi network:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Local WiFi Network                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Mac (Relay Server)          iPhone 1              iPhone 2         │
│   ┌─────────────────┐         ┌──────────┐         ┌──────────┐     │
│   │ OSC :5000       │◄────────│  Mind    │         │ OpenJaw  │     │
│   │ WebSocket :8765 │────────►│ Monitor  │         │   App    │     │
│   │ Bonjour ads     │         └──────────┘         └────┬─────┘     │
│   └─────────────────┘                                    │          │
│                                                          │ BLE      │
│                                                          ▼          │
│                                                    ┌──────────┐     │
│                                                    │  Apple   │     │
│                                                    │  Watch   │     │
│                                                    └──────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

The relay server advertises itself via Bonjour/mDNS, so the iOS app can auto-discover it without manual IP configuration.

---

## Repository Structure

```
OpenJaw/
├── v1/                          # Production system (Mind Monitor based)
│   ├── Skywalker/               # iOS + watchOS apps (Xcode project)
│   │   ├── Skywalker/           # iOS app source
│   │   │   ├── Models/          # Data models
│   │   │   ├── Views/           # SwiftUI views
│   │   │   ├── Services/        # WebSocket, Watch connectivity, etc.
│   │   │   └── Resources/       # Intervention catalog, bruxism info
│   │   └── Skywalker-Watch Watch App/  # watchOS app source
│   ├── relay-server/            # Python relay server
│   │   ├── server.py            # Main server (OSC → WebSocket)
│   │   ├── run.sh               # Startup script
│   │   └── requirements.txt
│   └── plan.md                  # Original technical design doc
│
├── v2/                          # Experimental (direct Muse connection)
│   └── muse-detector/           # Python detection server
│       ├── detector/            # Jaw clench detection algorithm
│       ├── ml/                  # ML-based detection (WIP)
│       ├── streaming/           # LSL receiver for OpenMuse
│       └── server/              # WebSocket + Bonjour
│
└── docs/                        # Research and documentation
    ├── Bruxism-research/        # Literature review
    └── OpenMuse/                # Muse protocol documentation
```

---

## Technical Details

### Detection Method

The Muse headband's TP9 and TP10 electrodes sit over the temporalis muscles. When you clench your jaw:

1. **EMG signals** (75-400 µV) from muscle contraction overwhelm the EEG signals (~10 µV)
2. This creates distinctive high-amplitude artifacts in the temporal channels
3. Mind Monitor (V1) or our custom algorithm (V2) detects these patterns
4. Detection triggers a WebSocket message to the iOS app
5. iOS app sends a message to the Watch via WatchConnectivity
6. Watch plays a haptic pattern

**Target latency:** < 500ms from clench to haptic

### Sleep Considerations

The system is designed for overnight use:
- Relay server uses `caffeinate` to prevent Mac sleep
- iOS app uses background audio to stay alive
- Watch app uses extended runtime sessions
- All connections have auto-reconnect logic

---

## Research Background

The `docs/Bruxism-research/` folder contains literature reviews on:
- Evidence-based interventions for bruxism
- Efficacy of different treatment approaches
- The muscle-tension chain from jaw to throat symptoms

---

## Contributing

This is a personal project built to solve my own bruxism. Contributions welcome!

Areas that need work:
- V2 detection algorithm tuning for sleep
- Android support
- Cloud sync for multi-device use
- Better overnight reliability testing

---

## License

MIT License — use freely, attribution appreciated.

---

## Acknowledgments

- [Mind Monitor](https://mind-monitor.com/) — excellent third-party Muse app
- [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse) — open-source Muse protocol implementation
- The Muse developer community for protocol documentation
