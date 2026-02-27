import Testing
@testable import Telocare

struct GardenNameResolverTests {
    private let resolver = GardenNameResolver()

    @Test func nodeAliasResolutionUsesCatalogFirst() {
        let title = resolver.nodeTitle(nodeID: "STRESS", fallbackLabel: "Stress & Anxiety\nOR 2.07")
        #expect(title == "Stress Load")
    }

    @Test func oneNodeLayerUsesNodeAlias() {
        let labelByID = ["GERD": "GERD / Silent Reflux\nOR 6.87"]
        let title = resolver.layerTitle(nodePath: ["GERD"], labelByID: labelByID)
        #expect(title == "Reflux Pressure")
    }

    @Test func twoNodeLayerUsesPathOrderWithPlusSeparator() {
        let labelByID = ["N1": "Alpha", "N2": "Beta"]
        let title = resolver.layerTitle(nodePath: ["N2", "N1"], labelByID: labelByID)
        #expect(title == "Beta + Alpha")
    }

    @Test func threeNodeLayerUsesCuratedLayerAlias() {
        let labelByID = [
            "STRESS": "Stress",
            "SLEEP_DEP": "Sleep Deprivation",
            "SYMPATHETIC": "Sympathetic Shift",
        ]
        let title = resolver.layerTitle(
            nodePath: ["SLEEP_DEP", "SYMPATHETIC", "STRESS"],
            labelByID: labelByID
        )
        #expect(title == "Arousal Loop")
    }

    @Test func unknownLayerAliasFallsBackDeterministicallyToSortedNodeTitles() {
        let labelByID = [
            "X3": "Gamma\nvalue",
            "X1": "Alpha",
            "X2": "Beta",
        ]

        let first = resolver.layerTitle(nodePath: ["X3", "X1", "X2"], labelByID: labelByID)
        let second = resolver.layerTitle(nodePath: ["X2", "X3", "X1"], labelByID: labelByID)

        #expect(first == "Alpha + Beta + Gamma")
        #expect(second == "Alpha + Beta + Gamma")
    }
}
