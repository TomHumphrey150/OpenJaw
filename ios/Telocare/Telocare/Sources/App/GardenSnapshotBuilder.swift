import Foundation

struct GardenSnapshotBuilder {
    func build(from inputs: [InputStatus]) -> [GardenSnapshot] {
        GardenPathway.allCases.map { pathway in
            let gardenInputs = inputs.filter { inputPathway(for: $0) == pathway }
            let activeInputs = gardenInputs.filter(\.isActive)
            let checkedCount = activeInputs.filter(\.isCheckedToday).count
            let activeCount = activeInputs.count

            let weeklyAverage: Double
            if activeInputs.isEmpty {
                weeklyAverage = 0
            } else {
                weeklyAverage = activeInputs.reduce(0.0) { $0 + $1.completion } / Double(activeInputs.count)
            }

            let todayRatio: Double
            if activeCount > 0 {
                todayRatio = Double(checkedCount) / Double(activeCount)
            } else {
                todayRatio = 0
            }

            let bloomLevel = (0.7 * todayRatio) + (0.3 * weeklyAverage)

            return GardenSnapshot(
                pathway: pathway,
                activeCount: activeCount,
                checkedTodayCount: checkedCount,
                weeklyAverage: weeklyAverage,
                bloomLevel: min(1.0, max(0.0, bloomLevel)),
                inputIDs: gardenInputs.map(\.id)
            )
        }
    }

    private func inputPathway(for input: InputStatus) -> GardenPathway {
        GardenPathway(causalPathway: input.causalPathway) ?? .midstream
    }
}
