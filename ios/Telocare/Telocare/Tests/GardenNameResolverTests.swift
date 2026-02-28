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

    @Test func twoNodeLayerUsesSortedNamesWithPlusSeparator() {
        let labelByID = ["N1": "Alpha", "N2": "Beta"]
        let title = resolver.layerTitle(nodePath: ["N2", "N1"], labelByID: labelByID)
        #expect(title == "Alpha + Beta")
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

    @Test func unknownLayerAliasFallsBackDeterministicallyToPrimaryNetworkName() {
        let labelByID = [
            "X3": "Gamma\nvalue",
            "X1": "Alpha",
            "X2": "Beta",
        ]

        let first = resolver.layerTitle(nodePath: ["X3", "X1", "X2"], labelByID: labelByID)
        let second = resolver.layerTitle(nodePath: ["X2", "X3", "X1"], labelByID: labelByID)

        #expect(first == "Alpha Network")
        #expect(second == "Alpha Network")
    }

    @Test func layerOverrideTakesPrecedence() {
        let override = GardenAliasOverride(
            signature: LayerSignature(nodeIDs: ["X1", "X2", "X3"]).rawValue,
            title: "Custom Loop",
            approvedAt: "2026-02-27T00:00:00Z",
            sourceGraphVersion: "graph-v1"
        )
        let resolver = GardenNameResolver(overrides: [override])
        let labelByID = ["X1": "Alpha", "X2": "Beta", "X3": "Gamma"]
        let title = resolver.layerTitle(nodePath: ["X3", "X1", "X2"], labelByID: labelByID)
        #expect(title == "Custom Loop")
    }
}
