import Testing
@testable import Telocare

struct CanonicalGraphLoaderTests {
    @Test func loadsFullCanonicalGraphFromBundledJSON() throws {
        let graph = try CanonicalGraphLoader.loadGraph()
        #expect(graph.nodes.count == 72)
        #expect(graph.edges.count == 120)
    }
}
