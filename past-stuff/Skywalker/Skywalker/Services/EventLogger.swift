//
//  EventLogger.swift
//  Skywalker
//
//  Bruxism Biofeedback - Event logging and persistence
//

import Foundation
import Observation

@Observable
@MainActor
class EventLogger {
    var events: [JawClenchEvent] = []

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var eventsFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("jaw_clench_events.json")
    }

    init() {
        loadEvents()
    }

    // MARK: - Public Methods

    func logEvent(_ event: JawClenchEvent) {
        events.append(event)
        saveEvents()
        print("[EventLogger] Logged event #\(event.count) at \(event.formattedTime)")
    }

    func clearEvents() {
        events.removeAll()
        saveEvents()
        print("[EventLogger] Cleared all events")
    }

    func exportEvents() -> String {
        let csvHeader = "ID,Timestamp,Count,FormattedTime\n"
        let csvRows = events.map { event in
            "\(event.id.uuidString),\(ISO8601DateFormatter().string(from: event.timestamp)),\(event.count),\(event.formattedTime)"
        }.joined(separator: "\n")

        return csvHeader + csvRows
    }

    // Get events for today
    func todayEvents() -> [JawClenchEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return events.filter { event in
            calendar.isDate(event.timestamp, inSameDayAs: today)
        }
    }

    // Get event count for today
    func todayEventCount() -> Int {
        return todayEvents().count
    }

    // MARK: - Private Methods

    private func saveEvents() {
        do {
            let data = try encoder.encode(events)
            try data.write(to: eventsFileURL, options: .atomic)
            print("[EventLogger] Saved \(events.count) events to disk")
        } catch {
            print("[EventLogger] Failed to save events: \(error.localizedDescription)")
        }
    }

    private func loadEvents() {
        guard fileManager.fileExists(atPath: eventsFileURL.path) else {
            print("[EventLogger] No events file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: eventsFileURL)
            events = try decoder.decode([JawClenchEvent].self, from: data)
            print("[EventLogger] Loaded \(events.count) events from disk")
        } catch {
            print("[EventLogger] Failed to load events: \(error.localizedDescription)")
            events = []
        }
    }
}
