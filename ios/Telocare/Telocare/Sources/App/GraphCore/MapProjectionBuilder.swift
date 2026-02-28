import Foundation

protocol MapProjectionBuilding {
    func build(graphData: CausalGraphData) -> MapProjection
}

struct MapProjectionBuilder: MapProjectionBuilding {
    func build(graphData: CausalGraphData) -> MapProjection {
        MapProjection(graphData: graphData)
    }
}

