# Bruxism Biofeedback Device: Product & Engineering Handoff

> **Status: Implemented.** This plan has been implemented and V1 is working. See [ONBOARDING.md](ONBOARDING.md) to get started.

**Related docs:** [Main README](../README.md) | [ONBOARDING.md](ONBOARDING.md) | [iOS App Setup](Skywalker/Claude.md) | [Relay Server](relay-server/README.md)

---

**Document Version:** 1.0
**Date:** January 30, 2026
**Original Status:** Discovery Complete, Ready for Development

---

## Executive Summary

We are building a **sleep bruxism (teeth grinding) biofeedback system** that detects jaw clenching in real-time and delivers haptic feedback via Apple Watch to interrupt the grinding behavior. The system uses an off-the-shelf consumer EEG headband (Muse S Athena) paired with an existing third-party app (Mind Monitor) for signal acquisition, with custom iOS and watchOS apps for the biofeedback delivery.

**Key Finding:** The detection component is already solved. Mind Monitor's built-in jaw clench detection works with the Athena headband and streams events over OSC protocol. Our engineering effort focuses on the delivery pipeline: receiving these events and triggering Watch haptics with minimal latency.

---

## Problem Statement

### Clinical Context
Sleep bruxism affects 8-13% of adults. Chronic grinding causes:
- Tooth damage and wear
- TMJ disorders
- Headaches and facial pain
- Sleep disruption

Current treatments (mouth guards) protect teeth but don't address the behavior. Biofeedback—delivering a gentle stimulus when grinding is detected—can train the brain to stop the behavior over time.

### User Need
A non-invasive, comfortable sleep monitoring system that:
1. Detects teeth grinding/clenching during sleep
2. Delivers immediate but gentle feedback (haptic vibration)
3. Logs events for morning review and trend tracking
4. Works reliably for 6-8 hours overnight

---

## Hardware Stack

### Primary Device: Muse S Athena (Owned)
- **Model:** MS-03 (2025 release)
- **Cost:** $475-520
- **Form Factor:** Soft fabric headband, designed for sleep use
- **Sensors:**
  - 4 EEG channels (TP9, AF7, AF8, TP10) at 256 Hz, 14-bit resolution
  - 4 auxiliary EEG channels
  - PPG (heart rate) at 64 Hz
  - Accelerometer/Gyroscope at 52 Hz
  - fNIRS (brain oxygenation) - not needed for this application
- **Connectivity:** Bluetooth Low Energy 5.3
- **Battery:** ~8-10 hours continuous use (sufficient for overnight)
- **Key Feature:** TP9 and TP10 electrodes sit directly over the temporalis muscle (jaw closing muscle). Jaw clenching produces high-amplitude EMG signals that appear as "artifacts" in the EEG—this is the signal we detect.

### Feedback Device: Apple Watch (Owned)
- Any Apple Watch with haptic engine (Series 3+)
- Worn on wrist during sleep
- Delivers haptic taps via WatchKit's `WKInterfaceDevice.current().play(.notification)` or custom haptic patterns

### Required Mobile Device
- iPhone (iOS 15+) running:
  - Mind Monitor app (signal acquisition)
  - Custom iOS app (event relay to Watch)
- Must remain on same WiFi network as any relay server

---

## Software Stack

### Signal Acquisition: Mind Monitor (Third-Party, Licensed)

**What it is:** A $15 iOS/Android app that connects to Muse headbands and provides:
- Real-time EEG visualization
- CSV data export
- OSC (Open Sound Control) streaming over WiFi
- Built-in blink and **jaw clench detection**

**Athena Compatibility:** Confirmed working as of v2.4.0 (April 2025)

**What we get from it:**
- `/muse/elements/jaw_clench` events streamed in real-time
- No algorithm development needed—detection is handled
- Raw EEG data available if we need custom detection later

**Licensing:** Consumer app, no API restrictions. OSC streaming is a documented feature intended for exactly this kind of integration.

**Limitations:**
- Closed source—we cannot modify the detection algorithm
- iOS background execution may be unreliable for overnight use
- Detection algorithm optimized for conscious use; sleep accuracy unvalidated

### Signal Validation: Completed

We have validated that Mind Monitor's jaw clench detection works with the Athena:

**Test Performed:** January 30, 2026
- Recorded session with deliberate jaw clenches
- CSV export shows `/muse/elements/jaw_clench` events at correct timestamps
- Detection appears responsive (<500ms latency from clench to event)

**Sample Data (from validation session):**
```
22:44:46.623  /muse/elements/jaw_clench
22:44:51.770  /muse/elements/jaw_clench  
22:44:53.522  /muse/elements/jaw_clench
22:44:53.760  /muse/elements/jaw_clench
22:45:02.763  /muse/elements/jaw_clench
```

**Unvalidated:** Detection accuracy during actual sleep. This requires overnight testing with ground truth (audio recording of grinding sounds).

---

## System Architecture

### Recommended Architecture: Local Network Relay

```
┌─────────────────┐      BLE       ┌─────────────────┐
│  Muse S Athena  │ ─────────────► │  Mind Monitor   │
│   (Headband)    │                │    (iPhone)     │
└─────────────────┘                └────────┬────────┘
                                            │ OSC/UDP
                                            │ WiFi
                                            ▼
                                   ┌─────────────────┐
                                   │   Relay Server  │
                                   │ (Mac/Raspberry  │
                                   │      Pi)        │
                                   └────────┬────────┘
                                            │ WebSocket or
                                            │ UDP Broadcast
                                            ▼
                                   ┌─────────────────┐
                                   │  Bruxism App    │
                                   │    (iPhone)     │
                                   └────────┬────────┘
                                            │ WatchConnectivity
                                            ▼
                                   ┌─────────────────┐
                                   │  Bruxism App    │
                                   │  (Apple Watch)  │
                                   │                 │
                                   │  ┌───────────┐  │
                                   │  │  HAPTIC   │  │
                                   │  │  FEEDBACK │  │
                                   │  └───────────┘  │
                                   └─────────────────┘
```

### Why This Architecture?

1. **Mind Monitor handles the hard part** (BLE protocol, signal processing, jaw detection)
2. **Relay server provides reliability** (iOS background execution is unreliable; a Mac or Pi stays awake)
3. **WebSocket gives low latency** (~100-300ms end-to-end, acceptable for biofeedback)
4. **WatchConnectivity is the official way** to communicate iPhone → Watch

### Alternative Architectures Considered

| Architecture | Pros | Cons | Verdict |
|--------------|------|------|---------|
| **iPhone-only (localhost OSC)** | Simplest, no extra hardware | iOS may throttle background listener; two apps competing for resources | Risky |
| **Push notifications** | Works anywhere | 1-3 second latency; too slow for biofeedback | Rejected |
| **Custom iOS app with direct BLE** | No Mind Monitor dependency | Requires reverse-engineering Athena protocol; 2-4 weeks extra work | Future option |
| **Local relay (recommended)** | Reliable, low latency | Requires always-on Mac or Pi | **Selected** |

---

## Technical Specifications

### OSC Protocol Details

Mind Monitor streams OSC messages over UDP. Relevant endpoints:

| OSC Address | Payload | Description |
|-------------|---------|-------------|
| `/muse/elements/jaw_clench` | `1` (integer) | Fired when jaw clench detected |
| `/muse/elements/blink` | `1` (integer) | Fired when eye blink detected |
| `/muse/eeg` | 4 floats | Raw EEG values (TP9, AF7, AF8, TP10) |
| `/muse/acc` | 3 floats | Accelerometer (X, Y, Z) |
| `/muse/elements/horseshoe` | 4 floats | Sensor contact quality (1=good, 2=medium, 4=bad) |

**Configuration in Mind Monitor:**
- Settings → OSC Stream Target IP: `<relay server IP>`
- Settings → OSC Stream Port: `5000` (default)
- Tap streaming icon to start

### Relay Server Implementation

Minimal Python server to receive OSC and broadcast to local network:

```python
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import socket

OSC_PORT = 5000
BROADCAST_PORT = 5001

broadcast_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

def jaw_handler(address, *args):
    print("Jaw clench detected, broadcasting...")
    broadcast_socket.sendto(b"JAW_CLENCH", ("<broadcast>", BROADCAST_PORT))

dispatcher = Dispatcher()
dispatcher.map("/muse/elements/jaw_clench", jaw_handler)

server = BlockingOSCUDPServer(("0.0.0.0", OSC_PORT), dispatcher)
server.serve_forever()
```

### iOS App Requirements

**Capabilities:**
- Background Modes: `audio` (for keeping connection alive) or `voip` push
- Local Network access (for receiving UDP broadcasts)
- WatchConnectivity framework

**Core Functionality:**
1. Listen for UDP broadcasts on port 5001
2. On receiving `JAW_CLENCH`, send message to Watch via `WCSession`
3. Log event with timestamp to local database
4. Morning: display event count and timeline

**Background Execution Strategy:**
- Use silent audio playback or VOIP push socket to maintain background execution
- Implement `beginBackgroundTask` for processing incoming events
- Handle app termination gracefully; persist state to disk

### watchOS App Requirements

**Functionality:**
1. Receive messages from iPhone via `WCSessionDelegate`
2. Trigger haptic feedback immediately
3. Optionally log event locally on Watch

**Haptic Options:**
```swift
// Simple notification tap
WKInterfaceDevice.current().play(.notification)

// Custom haptic pattern (more gentle for sleep)
WKInterfaceDevice.current().play(.click)

// Or use Core Haptics for custom patterns (watchOS 7+)
```

**Considerations:**
- Watch must not be in Theater Mode or Silent Mode
- Watch must maintain BLE connection to iPhone overnight
- Battery impact: minimal (haptics are low power)

---

## Open Questions & Risks

### Must Validate

| Question | How to Validate | Impact if False |
|----------|-----------------|-----------------|
| Does jaw clench detection work during sleep? | Overnight test with audio recording as ground truth | May need custom algorithm from raw EEG |
| Can Mind Monitor run reliably for 6-8 hours on iOS? | Multiple overnight tests | May need Android phone for Mind Monitor |
| Is haptic strong enough to interrupt grinding without waking user? | User testing | May need different feedback modality |
| Does end-to-end latency stay under 500ms? | Instrumented test | May need architecture changes |

### Known Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Mind Monitor app terminated by iOS overnight | Medium | High | Use Android for Mind Monitor; keep iPhone plugged in with Guided Access |
| Jaw detection generates excessive false positives during sleep | Medium | Medium | Implement cooldown period; tune sensitivity; fall back to custom algorithm |
| Watch disconnects from iPhone during sleep | Low | High | Ensure Watch is charged; test BLE reliability |
| User removes headband during sleep (discomfort) | Medium | Medium | User habituation; proper fit adjustment |
| Network reliability (WiFi drops) | Low | Medium | Implement reconnection logic; buffer events |

### Out of Scope (Future Enhancements)

- Custom jaw clench detection algorithm (bypassing Mind Monitor)
- Direct BLE connection from custom iOS app to Athena
- Sleep stage correlation (grinding mostly in N1/N2, rare in REM)
- Trend analysis and long-term tracking
- Cloud sync and multi-device support
- Android version

---

## Development Phases

### Phase 1: Proof of Concept (1 week)
**Goal:** Validate end-to-end signal flow with manual testing

**Deliverables:**
- [ ] Python relay server running on Mac
- [ ] Minimal iOS app that receives UDP and logs to console
- [ ] Minimal watchOS app that plays haptic on command
- [ ] Manual test: clench jaw → Watch vibrates

**Success Criteria:**
- Latency < 500ms from clench to haptic
- Works reliably for 10 consecutive clenches

### Phase 2: Overnight Stability (2 weeks)
**Goal:** Achieve reliable 6-8 hour operation

**Deliverables:**
- [ ] iOS app with proper background execution
- [ ] Reconnection logic for all network components
- [ ] Basic event logging with timestamps
- [ ] Overnight test protocol and results

**Success Criteria:**
- 3 consecutive nights with >90% uptime
- All components survive overnight without manual intervention

### Phase 3: Sleep Validation (2 weeks)
**Goal:** Validate detection accuracy during actual sleep

**Deliverables:**
- [ ] Ground truth collection method (audio recording)
- [ ] Analysis comparing Mind Monitor events to actual grinding
- [ ] Sensitivity/specificity metrics
- [ ] Decision: Mind Monitor detection sufficient, or custom algorithm needed?

**Success Criteria:**
- Sensitivity > 70% (catches most grinding events)
- False positive rate < 2 per hour

### Phase 4: MVP App (3 weeks)
**Goal:** Polished user experience for personal use

**Deliverables:**
- [ ] iOS app with setup flow, status dashboard, morning report
- [ ] watchOS app with haptic configuration options
- [ ] Relay server packaged for easy deployment (Docker or standalone)
- [ ] User documentation

**Success Criteria:**
- Non-technical user can set up and operate system
- Consistent nightly use for 2 weeks

---

## Resources & References

### Code Repositories
- [Mind Monitor Python Examples](https://github.com/Enigma644/MindMonitorPython) - Official samples for OSC reception
- [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse) - Athena protocol documentation (if custom BLE needed)
- [amused-py](https://github.com/Amused-EEG/amused-py) - Alternative Athena protocol implementation

### Documentation
- [Mind Monitor FAQ](https://mind-monitor.com/FAQ.php) - OSC streaming details
- [Mind Monitor Forums](https://mind-monitor.com/forums/) - Community support, Athena-specific threads
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity) - iPhone ↔ Watch communication

### Research Background
- Temporalis muscle EMG produces 75-400 µV signals vs ~10 µV for EEG (10-40x amplitude difference)
- TP9/TP10 electrode positions are directly over temporalis muscle
- RMMA (Rhythmic Masticatory Muscle Activity) pattern: 3+ consecutive bursts at ~1 Hz
- Muse validated for sleep staging with 86% accuracy vs clinical polysomnography

### Hardware Documentation
- [Muse S Athena Product Page](https://choosemuse.com/products/muse-s-athena)
- [Muse Developer Portal](https://choosemuse.com/pages/developers) - SDK access (gated)

---

## Appendix A: Validated Test Data

**File:** `mindMonitor_2026-01-30--22-44-46.csv`  
**Duration:** ~30 seconds  
**Conditions:** Awake, deliberate jaw clenches  

**Jaw Clench Events Detected:**
| Timestamp | Event |
|-----------|-------|
| 22:44:46.623 | jaw_clench |
| 22:44:51.770 | jaw_clench |
| 22:44:53.522 | jaw_clench |
| 22:44:53.760 | jaw_clench |
| 22:45:02.763 | jaw_clench |

**Signal Quality:** HSI values all 1 (good contact) throughout session.

**Observation:** Multiple clenches detected in rapid succession (53.522 and 53.760) suggests algorithm may fire multiple times for sustained clenches. Consider debouncing in relay server.

---

## Appendix B: Alternative Detection Approach

If Mind Monitor's detection proves inadequate for sleep, here is the fallback approach:

### Custom Algorithm from Raw EEG

1. **Receive raw EEG** via `/muse/eeg` OSC stream (4 channels at 256 Hz)
2. **Bandpass filter** TP9 and TP10 channels to 20-100 Hz (EMG band)
3. **Calculate RMS power** over 500ms sliding window
4. **Threshold detection:** If power > 3x baseline AND accelerometer stable → trigger event
5. **Debounce:** Minimum 2 seconds between events

**Estimated Development Time:** 1-2 weeks additional

**Advantages:**
- Full control over sensitivity/specificity
- Can tune for sleep-specific patterns
- No dependency on Mind Monitor's algorithm

**Disadvantages:**
- More complex
- Requires careful threshold calibration per user
- Must handle edge cases (REM eye movement, swallowing, head repositioning)

---

## Appendix C: Glossary

| Term | Definition |
|------|------------|
| **Bruxism** | Involuntary teeth grinding or jaw clenching, often during sleep |
| **EMG** | Electromyography; electrical signals from muscle activity |
| **EEG** | Electroencephalography; electrical signals from brain activity |
| **TP9/TP10** | Electrode positions over left/right temporal regions (behind ears) |
| **OSC** | Open Sound Control; UDP-based protocol for real-time data streaming |
| **RMMA** | Rhythmic Masticatory Muscle Activity; clinical signature of bruxism |
| **Temporalis** | Fan-shaped muscle on side of head responsible for jaw closing |
| **HSI** | Horseshoe Indicator; Muse's sensor contact quality metric |
| **fNIRS** | Functional Near-Infrared Spectroscopy; brain blood oxygenation measurement |

---

*Document prepared from technical feasibility research conducted January 2026.*