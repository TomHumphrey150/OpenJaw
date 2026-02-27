import Foundation

enum DoseValueFormatter {
    static func string(from value: Double) -> String {
        let roundedValue = value.rounded()
        if abs(roundedValue - value) < 0.0001 {
            return String(Int(roundedValue))
        }

        return String(format: "%.1f", value)
    }
}
