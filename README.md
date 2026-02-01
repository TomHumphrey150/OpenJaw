# OpenJaw

**Sleep bruxism biofeedback system** — detect teeth grinding in real-time and deliver gentle haptic feedback via Apple Watch to interrupt the behavior.

## What is this?

OpenJaw is a biofeedback system for sleep bruxism (teeth grinding). It uses a consumer EEG headband to detect jaw clenching during sleep, then delivers a gentle vibration through your Apple Watch to interrupt the grinding behavior before it causes damage.

**The goal:** Train your brain to stop grinding over time, rather than just protecting your teeth with a mouth guard.

## Why build this?

Sleep bruxism affects 8-13% of adults and causes:
- Tooth damage and wear
- TMJ disorders and jaw pain
- Headaches and facial pain
- Poor sleep quality

Current treatments (mouth guards, Botox) either just protect teeth or temporarily weaken muscles. Biofeedback is different — it can actually train the unconscious behavior to stop.

Commercial biofeedback devices exist but cost $500-2000+ and use proprietary hardware. OpenJaw uses consumer hardware you may already own and is completely open source.

---

## Current Status

| Version | Status | Description |
|---------|--------|-------------|
| **V1** | **Working** | Uses Mind Monitor app for detection. Requires two iPhones. |
| **V2** | Not working yet | Direct detection via ML. Needs more training data. |

**If you want to use this today, use V1.** See [Quick Start](#quick-start-v1) below.

---

## Hardware

### Current: Muse S Athena

We currently use the [Muse S Athena](https://choosemuse.com/products/muse-s-athena) (~$500), a consumer EEG headband designed for sleep. Its temporal electrodes (TP9/TP10) sit over the temporalis muscle — the main jaw-closing muscle. When you clench, EMG signals from the muscle create distinctive patterns we can detect.

**Limitations:** The Muse wasn't designed for jaw detection — it's an EEG device that happens to pick up jaw muscle signals as "artifacts." We're exploring alternatives that might be better suited for EMG detection specifically.

### Also Required
- **iPhone** (iOS 15+) for the OpenJaw app
- **Apple Watch** (Series 3+) for haptic feedback
- **Mac** for running the relay/detection server
- **Second iPhone** (V1 only) dedicated to running Mind Monitor

---

## How it works

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Muse S Athena  │  BLE    │    Detection    │   WiFi  │   iOS + Watch   │
│   (Headband)    │ ──────► │     Server      │ ──────► │     Apps        │
│                 │         │   (Mac/Python)  │         │                 │
└─────────────────┘         └─────────────────┘         └────────┬────────┘
                                                                  │
     Worn during sleep            Detects jaw                     ▼
     EEG + EMG signals            clenching              ┌─────────────────┐
                                                         │  Apple Watch    │
                                                         │   *buzz buzz*   │
                                                         └─────────────────┘
```

**Target latency:** < 500ms from clench to haptic feedback.

---

## Quick Start (V1)

V1 uses [Mind Monitor](https://mind-monitor.com/) ($15 iOS app) for jaw clench detection.

### 1. Start the relay server on your Mac

```bash
cd v1/relay-server
pip install -r requirements.txt
./run.sh
```

### 2. Configure Mind Monitor on iPhone 1

- Install Mind Monitor from App Store
- Connect to your Muse headband
- Settings → OSC Stream Target IP: `<your Mac's IP>`
- Settings → OSC Stream Port: `5000`
- Start streaming (tap the OSC icon)

### 3. Install OpenJaw on iPhone 2

- Open `v1/Skywalker/Skywalker.xcodeproj` in Xcode
- Build and run on your iPhone
- The app will auto-discover the relay server

### 4. Install Watch app

- Select the Watch target in Xcode
- Build and run on your paired Apple Watch

### 5. Test it

- Clench your jaw while wearing the Muse
- Your Watch should vibrate within ~500ms

For detailed setup instructions, see [`v1/Skywalker/Claude.md`](v1/Skywalker/Claude.md).

---

## V1 vs V2 Architecture

### V1: Two-iPhone Architecture (Working)

```
Muse ──► iPhone 1 (Mind Monitor) ──► Mac (Relay) ──► iPhone 2 (OpenJaw) ──► Watch
```

Uses Mind Monitor's built-in jaw clench detection. Reliable but requires two iPhones because Mind Monitor must stay in the foreground.

**Documentation:**
- [`v1/plan.md`](v1/plan.md) — Full technical design document
- [`v1/Skywalker/Claude.md`](v1/Skywalker/Claude.md) — iOS/watchOS app setup
- [`v1/relay-server/README.md`](v1/relay-server/README.md) — Relay server details

### V2: Direct ML Detection (Not Working Yet)

```
Muse ──► Mac (OpenMuse + ML Detector) ──► iPhone (OpenJaw) ──► Watch
```

Bypasses Mind Monitor using [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse) for direct Bluetooth connection and a custom ML model for detection.

**Why it doesn't work yet:** The ML model needs training data, and collecting training data means deliberately clenching your jaw — the exact behavior we're trying to stop. This creates a fundamental contradiction for bruxism sufferers.

**The plan:** Use V1 to bootstrap V2. While V1 runs normally, it logs sensor data with labels from its threshold-based detector. Over weeks/months of normal use, this accumulates enough real-world training data (from involuntary sleep clenches) to train the V2 ML model — without anyone having to deliberately clench.

**Documentation:**
- [`v2/muse-detector/docs/HYBRID_BOOTSTRAP_DESIGN.md`](v2/muse-detector/docs/HYBRID_BOOTSTRAP_DESIGN.md) — The V1→V2 bootstrap plan
- [`v2/muse-detector/docs/learnings/002-ml-approach-problems.md`](v2/muse-detector/docs/learnings/002-ml-approach-problems.md) — Why ML is hard for this problem
- [`v2/muse-detector/docs/ML_SYSTEM_DESIGN.md`](v2/muse-detector/docs/ML_SYSTEM_DESIGN.md) — ML architecture details

---

## The iOS App

Beyond biofeedback, the OpenJaw iOS app includes:

### Daily Habits
Evidence-based interventions for managing bruxism:
- Daytime awareness reminders
- Lifestyle tracking (caffeine, alcohol, stress)
- Jaw exercises and massage techniques

### Progress Tracking
- Nightly event counts and trends
- Week-over-week comparisons
- HealthKit sleep data integration

---

## Repository Structure

```
OpenJaw/
├── v1/                          # Production system (Mind Monitor based)
│   ├── Skywalker/               # iOS + watchOS Xcode project
│   ├── relay-server/            # Python relay server
│   └── plan.md                  # Technical design document
│
├── v2/                          # Experimental (direct ML detection)
│   └── muse-detector/           # Python ML detector
│       └── docs/                # Design docs and learnings
│
└── docs/                        # Research and documentation
    └── Bruxism-research/        # Literature review
```

---

## Research

The [`docs/Bruxism-research/`](docs/Bruxism-research/) folder contains literature reviews on evidence-based interventions for bruxism, compiled from systematic reviews and meta-analyses.

---

## Contributing

This is a personal project built to solve my own bruxism. Contributions welcome!

**Areas that need work:**
- Better hardware for jaw muscle detection (alternatives to Muse)
- V2 ML model improvements
- Android support
- Overnight reliability testing

---

## License

MIT License — use freely, attribution appreciated.

---

## Acknowledgments

- [Mind Monitor](https://mind-monitor.com/) — third-party Muse app
- [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse) — open-source Muse protocol
