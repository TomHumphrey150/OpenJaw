import Foundation

enum CanonicalGraphLoader {
    private static let cachedGraph = loadGraphOrLegacyFallback()

    static func loadGraph() throws -> CausalGraphData {
        guard let resourceURL = defaultGraphResourceURL() else {
            throw CanonicalGraphLoaderError.resourceNotFound
        }

        let data = try Data(contentsOf: resourceURL)
        return try JSONDecoder().decode(CausalGraphData.self, from: data)
    }

    static func loadGraphOrFallback() -> CausalGraphData {
        cachedGraph
    }

    private static func loadGraphOrLegacyFallback() -> CausalGraphData {
        do {
            return try loadGraph()
        } catch {
            return .defaultGraph
        }
    }

    private static func defaultGraphResourceURL() -> URL? {
        for bundle in candidateBundles() {
            if let scopedURL = bundle.url(forResource: "default-graph", withExtension: "json", subdirectory: "Graph") {
                return scopedURL
            }

            if let rootURL = bundle.url(forResource: "default-graph", withExtension: "json") {
                return rootURL
            }
        }

        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        let all = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        var seen = Set<String>()
        return all.filter { bundle in
            seen.insert(bundle.bundlePath).inserted
        }
    }
}

enum CanonicalGraphLoaderError: Error {
    case resourceNotFound
}
