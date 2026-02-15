//
//  WatchConnectivityManager.swift
//  Skywalker-Watch Watch App
//
//  Bruxism Biofeedback - WatchConnectivity receiver for Apple Watch
//

import Foundation
import Observation
import WatchConnectivity
import WatchKit

@Observable
@MainActor
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    var isConnectedToPhone: Bool = false
    var lastHapticTime: Date?
    var totalEvents: Int = 0
    var lastPattern: HapticPattern = .singleTap
    var lastMessageReceived: String = "None"

    private var session: WCSession?
    private let hapticEngine = HapticEngine()
    private var extendedRuntimeSession: WKExtendedRuntimeSession?

    override init() {
        super.init()

        print("[Watch] WatchConnectivityManager init()")

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            print("[Watch] Session delegate set, activating...")
            session?.activate()
            print("[Watch] WatchConnectivity session initialized")
            print("[Watch] Session reachable: \(session?.isReachable ?? false)")
            print("[Watch] Activation state will be reported in delegate callback")
        } else {
            print("[Watch] WatchConnectivity not supported on this device")
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[Watch] Activation failed: \(error.localizedDescription)")
                return
            }

            print("[Watch] ✅ Activation complete - state: \(activationState.rawValue)")
            print("[Watch] ✅ isReachable: \(session.isReachable)")
            updateConnectionStatus(session)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            print("[Watch] Reachability changed: \(session.isReachable)")
            updateConnectionStatus(session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("[Watch] 🔵 didReceiveMessage called (NO reply handler)")
        print("[Watch] 🔵 Message: \(message)")
        Task { @MainActor in
            print("[Watch] 🔵 Handling message on MainActor")
            handleMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("[Watch] 🟢 didReceiveMessage called (WITH reply handler)")
        print("[Watch] 🟢 Received at: \(Date())")
        print("[Watch] 🟢 Message timestamp from iPhone: \(message["timestamp"] ?? "none")")
        print("[Watch] 🟢 Message: \(message)")
        Task { @MainActor in
            print("[Watch] 🟢 Handling message on MainActor")
            handleMessage(message)
            replyHandler(["status": "received"])
        }
    }

    /// Handle queued messages from transferUserInfo (when watch was not reachable)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("[Watch] 🟡 didReceiveUserInfo called (queued message)")
        print("[Watch] 🟡 UserInfo: \(userInfo)")
        Task { @MainActor in
            print("[Watch] 🟡 Handling queued message on MainActor")
            handleMessage(userInfo)
        }
    }

    // MARK: - Public Methods

    func testHaptic() {
        print("[Watch] Manual haptic test triggered")
        totalEvents += 1
        lastHapticTime = Date()
        lastPattern = .singleTap
        lastMessageReceived = "Local test"
        hapticEngine.play(.singleTap)
    }

    /// Request extended runtime to keep the app alive during sleep
    /// Uses "self-care" session type which is appropriate for health monitoring
    func requestExtendedRuntime() {
        // Don't start if already running
        if extendedRuntimeSession?.state == .running {
            print("[Watch] Extended runtime already running")
            return
        }

        extendedRuntimeSession = WKExtendedRuntimeSession()
        extendedRuntimeSession?.delegate = self
        extendedRuntimeSession?.start()
        print("[Watch] Extended runtime session requested")
    }

    func stopExtendedRuntime() {
        extendedRuntimeSession?.invalidate()
        extendedRuntimeSession = nil
        print("[Watch] Extended runtime session stopped")
    }

    // MARK: - Private Methods

    private func updateConnectionStatus(_ session: WCSession) {
        isConnectedToPhone = session.isReachable
    }

    private func handleMessage(_ message: [String: Any]) {
        lastMessageReceived = "\(message)"

        print("[Watch] 📥 handleMessage() called with action: \(message["action"] ?? "NONE")")

        guard let action = message["action"] as? String else {
            print("[Watch] Message missing 'action' field")
            return
        }

        switch action {
        case "haptic":
            handleHapticTrigger(message)
        case "ping":
            // Just acknowledge - no haptic needed
            print("[Watch] Ping received, acknowledging")
        default:
            print("[Watch] Unknown action: \(action)")
        }
    }

    private func handleHapticTrigger(_ message: [String: Any]) {
        print("[Watch] 🎯 handleHapticTrigger() called")
        print("[Watch] 🎯 Pattern from message: \(message["pattern"] ?? "NONE")")

        // Parse haptic pattern
        let pattern: HapticPattern
        if let patternRaw = message["pattern"] as? String,
           let parsedPattern = HapticPattern(rawValue: patternRaw) {
            pattern = parsedPattern
        } else {
            pattern = .singleTap // Default
        }

        // Update stats
        totalEvents += 1
        lastHapticTime = Date()
        lastPattern = pattern

        print("[Watch] 🎯 Stats updated - totalEvents: \(totalEvents), lastPattern: \(lastPattern.displayName)")
        print("[Watch] 🎯 About to call hapticEngine.play(\(pattern.displayName))")

        // Play haptic
        hapticEngine.play(pattern)

        print("[Watch] 🎯 hapticEngine.play() call completed")
        print("[Watch] Played haptic pattern: \(pattern.displayName) (Event #\(totalEvents))")
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WatchConnectivityManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            print("[Watch] ✅ Extended runtime session started - app will stay active")
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            print("[Watch] ⚠️ Extended runtime session will expire soon")
            // Request a new session before this one expires
            self.requestExtendedRuntime()
        }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        Task { @MainActor in
            print("[Watch] Extended runtime session invalidated: \(reason.rawValue)")
            if let error = error {
                print("[Watch] Extended runtime error: \(error.localizedDescription)")
            }

            // Automatically restart if it wasn't intentional
            if reason != .none {
                print("[Watch] Attempting to restart extended runtime...")
                // Small delay before restarting
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                self.requestExtendedRuntime()
            }
        }
    }
}
