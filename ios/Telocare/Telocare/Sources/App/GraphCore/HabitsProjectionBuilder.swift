import Foundation

protocol HabitsProjectionBuilding {
    func build(inputs: [InputStatus]) -> HabitsProjection
}

struct HabitsProjectionBuilder: HabitsProjectionBuilding {
    func build(inputs: [InputStatus]) -> HabitsProjection {
        HabitsProjection(
            title: "Health Gardens",
            inputs: inputs
        )
    }
}

