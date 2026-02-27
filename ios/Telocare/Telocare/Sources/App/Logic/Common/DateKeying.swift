import Foundation

enum DateKeying {
    static func localDateKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func timestamp(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func timestampNow() -> String {
        timestamp(from: Date())
    }
}
