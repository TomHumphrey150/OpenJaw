//
//  WatchConnectivityService.swift
//  Skywalker
//
//  Bruxism Biofeedback - WatchConnectivity for iPhone <-> Apple Watch communication
//

import Foundation
import Observation
import SwiftUI
import WatchConnectivity

@Observable
@MainActor
class WatchConnectivityService: NSObject {
    var watchReachable: Bool = false
    var isPaired: Bool = false
    var isWatchAppInstalled: Bool = false
    var lastWatchResponse: Date?

    private var session: WCSession?
    private var hapticPattern: HapticPattern = .singleTap

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("[WatchConnectivity] Session activated")
        } else {
            print("[WatchConnectivity] WatchConnectivity not supported on this device")
        }
    }

    // MARK: - Public Methods

    func sendHapticTrigger(pattern: HapticPattern? = nil) {
        let patternToUse = pattern ?? self.hapticPattern

        print("[WatchConnectivity] 📤 sendHapticTrigger() called")

        guard let session = session else {
            print("[WatchConnectivity] ❌ Session not initialized")
            return
        }

        print("[WatchConnectivity] Session state: \(session.activationState.rawValue)")
        print("[WatchConnectivity] isPaired: \(session.isPaired)")
        print("[WatchConnectivity] isWatchAppInstalled: \(session.isWatchAppInstalled)")
        print("[WatchConnectivity] isReachable: \(session.isReachable)")

        let message: [String: Any] = [
            "action": "haptic",
            "pattern": patternToUse.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        // Always try sendMessage first - it often works even when isReachable is false
        // Only fall back to transferUserInfo if sendMessage actually fails
        print("[WatchConnectivity] 📤 Attempting sendMessage (isReachable: \(session.isReachable))...")

        session.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.lastWatchResponse = Date()
                print("[WatchConnectivity] ✅ Watch replied: \(reply)")
            }
        }, errorHandler: { [weak self] error in
            print("[WatchConnectivity] ❌ sendMessage failed: \(error.localizedDescription)")
            print("[WatchConnectivity] 📤 Falling back to transferUserInfo (queued)...")
            // Fallback to transferUserInfo which queues for later delivery
            self?.session?.transferUserInfo(message)
        })

        print("[WatchConnectivity] 📤 Sent haptic trigger: \(patternToUse.displayName)")
    }

    func updateHapticPattern(_ pattern: HapticPattern) {
        self.hapticPattern = pattern
        print("[WatchConnectivity] Updated haptic pattern to: \(pattern.displayName)")
    }

    func sendTestHaptic() {
        sendHapticTrigger()
        print("[WatchConnectivity] Manual test haptic sent")
    }

    func verifyWatchConnection() {
        guard let session = session else {
            print("[WatchConnectivity] Cannot verify - session not initialized")
            return
        }

        let message: [String: Any] = [
            "action": "ping",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { [weak self] _ in
            Task { @MainActor in
                self?.lastWatchResponse = Date()
                print("[WatchConnectivity] ✅ Watch ping successful")
            }
        }, errorHandler: { error in
            print("[WatchConnectivity] Verify failed: \(error.localizedDescription)")
        })
    }

    // MARK: - Watch Status Display

    var watchStatusText: String {
        guard let lastResponse = lastWatchResponse else {
            return "Unknown"
        }
        let interval = Date().timeIntervalSince(lastResponse)
        if interval < 10 {
            return "Responding"
        } else if interval < 60 {
            return "Active (\(Int(interval))s ago)"
        } else if interval < 300 {
            return "Active (\(Int(interval / 60))m ago)"
        } else {
            return "Last seen \(Int(interval / 60))m ago"
        }
    }

    var watchStatusColor: Color {
        guard let lastResponse = lastWatchResponse else {
            return .secondary  // Unknown = gray
        }
        let interval = Date().timeIntervalSince(lastResponse)
        if interval < 60 {
            return .green
        } else if interval < 300 {
            return .yellow
        } else {
            return .orange
        }
    }

    var watchStatusIcon: String {
        guard let lastResponse = lastWatchResponse else {
            return "questionmark.circle"
        }
        let interval = Date().timeIntervalSince(lastResponse)
        if interval < 60 {
            return "checkmark.circle.fill"
        } else {
            return "clock"
        }
    }

    // MARK: - Private Methods

    private func updateReachability() {
        guard let session = session else { return }

        DispatchQueue.main.async {
            self.watchReachable = session.isReachable
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WatchConnectivity] Activation failed: \(error.localizedDescription)")
            return
        }

        print("[WatchConnectivity] ✅ Activation complete")
        print("[WatchConnectivity]    - State: \(activationState.rawValue)")
        print("[WatchConnectivity]    - isPaired: \(session.isPaired)")
        print("[WatchConnectivity]    - isWatchAppInstalled: \(session.isWatchAppInstalled)")
        print("[WatchConnectivity]    - isReachable: \(session.isReachable)")
        updateReachability()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchConnectivity] Session became inactive")
        updateReachability()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivity] Session deactivated")
        updateReachability()

        // Reactivate the session
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivity] Reachability changed: \(session.isReachable)")
        updateReachability()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("[WatchConnectivity] Received message from watch: \(message)")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("[WatchConnectivity] Received message from watch with reply handler: \(message)")
        replyHandler(["status": "received"])
    }
}
