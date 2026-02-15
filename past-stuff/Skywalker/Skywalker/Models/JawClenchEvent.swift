//
//  JawClenchEvent.swift
//  Skywalker
//
//  Bruxism Biofeedback - Jaw clench event model
//

import Foundation

struct JawClenchEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let count: Int

    init(id: UUID = UUID(), timestamp: Date = Date(), count: Int) {
        self.id = id
        self.timestamp = timestamp
        self.count = count
    }

    // Initialize from WebSocket JSON payload
    init(from json: [String: Any]) throws {
        self.id = UUID()

        // Parse timestamp
        if let timestampString = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            self.timestamp = formatter.date(from: timestampString) ?? Date()
        } else {
            self.timestamp = Date()
        }

        // Parse count
        self.count = json["count"] as? Int ?? 0
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: timestamp)
    }
}
