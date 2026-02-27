import Foundation

struct GardenThemeResolver {
    private let themes = GardenThemeKey.allCases

    func themeForRoot(nodeID: String) -> GardenThemeKey {
        guard !themes.isEmpty else {
            return .meadow
        }

        let hashValue = stableHash(of: nodeID)
        return themes[hashValue % themes.count]
    }

    func themeForCluster(nodeID: String, branchRootNodeID: String?) -> GardenThemeKey {
        if let branchRootNodeID {
            return themeForRoot(nodeID: branchRootNodeID)
        }

        return themeForRoot(nodeID: nodeID)
    }

    private func stableHash(of value: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        return Int(hash & 0x7fff_ffff_ffff_ffff)
    }
}
