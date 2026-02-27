import Foundation

struct GardenGridLayout {
    func rows<T>(from items: [T]) -> [[T]] {
        guard !items.isEmpty else {
            return []
        }

        return stride(from: 0, to: items.count, by: 2).map { startIndex in
            let endIndex = min(startIndex + 2, items.count)
            return Array(items[startIndex..<endIndex])
        }
    }
}
