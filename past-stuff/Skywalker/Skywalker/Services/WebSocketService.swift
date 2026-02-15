//
//  WebSocketService.swift
//  Skywalker
//
//  Bruxism Biofeedback - WebSocket client for relay server connection
//

import Foundation
import Observation

@Observable
@MainActor
class WebSocketService: NSObject, URLSessionWebSocketDelegate {
    var isConnected: Bool = false
    var lastEventTime: Date?
    var totalEvents: Int = 0
    var connectionTime: Date?

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private var urlSession: URLSession?

    private let watchService: WatchConnectivityService
    private let eventLogger: EventLogger

    private let reconnectInterval: TimeInterval = 5.0

    init(watchService: WatchConnectivityService, eventLogger: EventLogger) {
        self.watchService = watchService
        self.eventLogger = eventLogger
        super.init()

        // Create URL session with self as delegate
        self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    }

    // MARK: - Connection Management

    func connect(to url: URL) {
        disconnect()

        print("[WebSocket] Connecting to \(url.absoluteString)...")

        guard let session = urlSession else { return }
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        // Start listening for messages
        receiveMessage()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionTime = nil
        }

        print("[WebSocket] Disconnected")
    }

    func startAutoReconnect(to url: URL) {
        reconnectTimer?.invalidate()

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: true) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }

            print("[WebSocket] Auto-reconnect attempt...")
            self.connect(to: url)
        }
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue listening for next message
                self.receiveMessage()

            case .failure(let error):
                print("[WebSocket] Receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.connectionTime = nil
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("[WebSocket] Received: \(text)")
            handleJSONMessage(text)

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                print("[WebSocket] Received data: \(text)")
                handleJSONMessage(text)
            }

        @unknown default:
            print("[WebSocket] Unknown message type")
        }
    }

    private func handleJSONMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["event"] as? String else {
            print("[WebSocket] Failed to parse JSON")
            return
        }

        print("[WebSocket] Event type: \(eventType)")

        switch eventType {
        case "connected":
            handleConnectedEvent(json)

        case "jaw_clench":
            handleJawClenchEvent(json)

        default:
            print("[WebSocket] Unknown event type: \(eventType)")
        }
    }

    private func handleConnectedEvent(_ json: [String: Any]) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionTime = Date()

            if let totalEvents = json["total_events"] as? Int {
                self.totalEvents = totalEvents
            }
        }

        print("[WebSocket] Connected to relay server")
    }

    private func handleJawClenchEvent(_ json: [String: Any]) {
        do {
            let event = try JawClenchEvent(from: json)

            DispatchQueue.main.async {
                self.lastEventTime = event.timestamp
                self.totalEvents = event.count

                // Log event
                self.eventLogger.logEvent(event)

                // Trigger watch haptic
                print("[WebSocket] 🎯 About to trigger watch haptic for event #\(event.count)")
                print("[WebSocket] 🎯 Watch service reachable: \(self.watchService.watchReachable)")
                self.watchService.sendHapticTrigger()
                print("[WebSocket] 🎯 Haptic trigger call completed")
            }

            print("[WebSocket] Jaw clench event #\(event.count) at \(event.formattedTime)")

        } catch {
            print("[WebSocket] Failed to parse jaw clench event: \(error)")
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[WebSocket] Connection opened")
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionTime = Date()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WebSocket] Connection closed with code: \(closeCode.rawValue)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionTime = nil
        }
    }
}
