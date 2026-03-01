import Foundation

struct GardenHierarchyBuilder {
    private static let maxTopLevelClusters = 6

    private let themeResolver: GardenThemeResolver
    private let nameResolver: GardenNameResolver

    init(
        themeResolver: GardenThemeResolver = GardenThemeResolver(),
        nameResolver: GardenNameResolver = GardenNameResolver()
    ) {
        self.themeResolver = themeResolver
        self.nameResolver = nameResolver
    }

    func build(
        inputs: [InputStatus],
        graphData: CausalGraphData,
        selection: GardenHierarchySelection
    ) -> GardenHierarchyBuildResult {
        let initialInputs = inputs
        let index = GraphHierarchyIndex(graphData: graphData, inputs: initialInputs, nameResolver: nameResolver)

        var currentInputs = initialInputs
        var resolvedNodePath: [String] = []
        var resolvedClusterPath: [GardenClusterSnapshot] = []
        var excludedNodeIDs = Set<String>()
        var levels: [GardenHierarchyLevel] = []
        var branchRootNodeID: String?

        while true {
            let clusters = buildClusters(
                currentInputs: currentInputs,
                excludedNodeIDs: excludedNodeIDs,
                index: index,
                branchRootNodeID: branchRootNodeID,
                depth: resolvedNodePath.count
            )

            levels.append(
                GardenHierarchyLevel(
                    depth: resolvedNodePath.count,
                    clusters: clusters
                )
            )

            guard resolvedNodePath.count < selection.selectedNodePath.count else {
                break
            }

            let selectedNodeID = selection.selectedNodePath[resolvedNodePath.count]
            guard let selectedCluster = clusters.first(where: { $0.nodeID == selectedNodeID }) else {
                break
            }

            let selectedInputIDs = Set(selectedCluster.inputIDs)
            currentInputs = currentInputs.filter { selectedInputIDs.contains($0.id) }
            resolvedNodePath.append(selectedNodeID)
            resolvedClusterPath.append(selectedCluster)
            excludedNodeIDs.formUnion(selectedCluster.nodeIDs)
            if branchRootNodeID == nil {
                branchRootNodeID = selectedCluster.nodeID
            }
        }

        return GardenHierarchyBuildResult(
            filteredInputs: currentInputs,
            levels: levels,
            resolvedNodePath: resolvedNodePath,
            resolvedClusterPath: resolvedClusterPath
        )
    }

    func nodeTitle(
        for nodeID: String,
        in graphData: CausalGraphData
    ) -> String {
        let labelByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data.label) })
        let clusterNodeIDs = clusterNodeIDs(from: nodeID)
        if clusterNodeIDs.count > 1 {
            return nameResolver.layerTitle(nodePath: clusterNodeIDs, labelByID: labelByID)
        }

        return nameResolver.nodeTitle(nodeID: nodeID, fallbackLabel: labelByID[nodeID])
    }

    func layerTitle(
        for nodePath: [String],
        in graphData: CausalGraphData
    ) -> String {
        let labelByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data.label) })
        return nameResolver.layerTitle(nodePath: nodePath, labelByID: labelByID)
    }

    func leafCluster(
        nodePath: [String],
        filteredInputs: [InputStatus],
        graphData: CausalGraphData
    ) -> GardenClusterSnapshot? {
        guard let currentNodeID = nodePath.last else {
            return nil
        }

        let labelByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data.label) })
        let metrics = clusterMetrics(for: filteredInputs)
        let nodeIDs = clusterNodeIDs(from: currentNodeID)
        let title = nameResolver.layerTitle(nodePath: nodeIDs, labelByID: labelByID)
        let branchRootNodeID = nodePath.first

        return GardenClusterSnapshot(
            nodeID: currentNodeID,
            nodeIDs: nodeIDs,
            title: title,
            inputIDs: filteredInputs.map(\.id).sorted(),
            activeCount: metrics.activeCount,
            checkedTodayCount: metrics.checkedTodayCount,
            bloomLevel: metrics.bloomLevel,
            themeKey: themeResolver.themeForCluster(nodeID: currentNodeID, branchRootNodeID: branchRootNodeID)
        )
    }

    private func buildClusters(
        currentInputs: [InputStatus],
        excludedNodeIDs: Set<String>,
        index: GraphHierarchyIndex,
        branchRootNodeID: String?,
        depth: Int
    ) -> [GardenClusterSnapshot] {
        guard !currentInputs.isEmpty else {
            return []
        }

        let weightedClusters = weightedClusters(
            currentInputs: currentInputs,
            excludedNodeIDs: excludedNodeIDs,
            index: index,
            depth: depth
        )
        let inputByID = Dictionary(uniqueKeysWithValues: currentInputs.map { ($0.id, $0) })

        return weightedClusters.compactMap { cluster in
            let groupedInputs = cluster.inputIDs.compactMap { inputByID[$0] }
            guard !groupedInputs.isEmpty else {
                return nil
            }

            let metrics = clusterMetrics(for: groupedInputs)
            let title = nameResolver.layerTitle(nodePath: cluster.nodeIDs, labelByID: index.nodeLabelByID)
            return GardenClusterSnapshot(
                nodeID: cluster.signature.rawValue,
                nodeIDs: cluster.nodeIDs,
                title: title,
                inputIDs: groupedInputs.map(\.id).sorted(),
                activeCount: metrics.activeCount,
                checkedTodayCount: metrics.checkedTodayCount,
                bloomLevel: metrics.bloomLevel,
                themeKey: themeResolver.themeForCluster(
                    nodeID: cluster.signature.rawValue,
                    branchRootNodeID: branchRootNodeID
                )
            )
        }
        .sorted { lhs, rhs in
            let lhsCoverage = weightedCoverage(of: lhs, index: index)
            let rhsCoverage = weightedCoverage(of: rhs, index: index)
            if lhsCoverage != rhsCoverage {
                return lhsCoverage > rhsCoverage
            }
            if lhs.inputIDs.count != rhs.inputIDs.count {
                return lhs.inputIDs.count > rhs.inputIDs.count
            }
            let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return lhs.nodeID < rhs.nodeID
        }
    }

    private func weightedClusters(
        currentInputs: [InputStatus],
        excludedNodeIDs: Set<String>,
        index: GraphHierarchyIndex,
        depth: Int
    ) -> [WeightedGardenCluster] {
        var affinityByNodeByInputID: [String: [String: Double]] = [:]

        for input in currentInputs {
            let affinities = index.targetAffinitiesByInputID[input.id] ?? [:]
            for (nodeID, affinity) in affinities {
                guard !excludedNodeIDs.contains(nodeID) else {
                    continue
                }
                guard affinity > 0 else {
                    continue
                }
                affinityByNodeByInputID[nodeID, default: [:]][input.id, default: 0] += affinity
            }
        }

        let parentCount = currentInputs.count
        var clusters = affinityByNodeByInputID.compactMap { nodeID, affinityByInputID in
            let inputIDs = affinityByInputID.keys.sorted()
            guard !inputIDs.isEmpty else {
                return nil
            }
            guard inputIDs.count < parentCount else {
                return nil
            }

            let weightedCoverage = affinityByInputID.values.reduce(0, +)
            return WeightedGardenCluster(
                signature: GardenClusterSignature(nodeIDs: [nodeID]),
                nodeIDs: [nodeID],
                inputIDs: inputIDs,
                weightedCoverage: weightedCoverage,
                affinityByInputID: affinityByInputID
            )
        }
        .sorted(by: compareWeightedClusters)

        if depth == 0 && clusters.count > Self.maxTopLevelClusters {
            clusters = cappedTopLevelClusters(clusters)
        }

        return clusters
    }

    private func cappedTopLevelClusters(_ clusters: [WeightedGardenCluster]) -> [WeightedGardenCluster] {
        var current = clusters
        while current.count > Self.maxTopLevelClusters {
            guard let pair = mostOverlappingPair(in: current) else {
                break
            }

            let merged = merge(lhs: current[pair.0], rhs: current[pair.1])
            let minIndex = min(pair.0, pair.1)
            let maxIndex = max(pair.0, pair.1)
            current.remove(at: maxIndex)
            current.remove(at: minIndex)
            current.append(merged)
            current.sort(by: compareWeightedClusters)
        }
        return current
    }

    private func mostOverlappingPair(in clusters: [WeightedGardenCluster]) -> (Int, Int)? {
        guard clusters.count > 1 else {
            return nil
        }

        var bestPair: (Int, Int)?
        var bestScore = -1.0
        var bestTieBreaker = ""

        for lhsIndex in clusters.indices {
            for rhsIndex in clusters.indices where rhsIndex > lhsIndex {
                let lhs = clusters[lhsIndex]
                let rhs = clusters[rhsIndex]
                let score = weightedJaccard(lhs.affinityByInputID, rhs.affinityByInputID)
                let tieBreaker = [lhs.signature.rawValue, rhs.signature.rawValue].sorted().joined(separator: "::")

                if score > bestScore {
                    bestScore = score
                    bestPair = (lhsIndex, rhsIndex)
                    bestTieBreaker = tieBreaker
                    continue
                }

                if score == bestScore && tieBreaker < bestTieBreaker {
                    bestPair = (lhsIndex, rhsIndex)
                    bestTieBreaker = tieBreaker
                }
            }
        }

        return bestPair
    }

    private func merge(lhs: WeightedGardenCluster, rhs: WeightedGardenCluster) -> WeightedGardenCluster {
        let nodeIDs = Array(Set(lhs.nodeIDs).union(rhs.nodeIDs)).sorted()
        let inputIDs = Array(Set(lhs.inputIDs).union(rhs.inputIDs)).sorted()
        var affinityByInputID = lhs.affinityByInputID
        for (inputID, rhsAffinity) in rhs.affinityByInputID {
            let lhsAffinity = affinityByInputID[inputID] ?? 0
            affinityByInputID[inputID] = max(lhsAffinity, rhsAffinity)
        }

        return WeightedGardenCluster(
            signature: GardenClusterSignature(nodeIDs: nodeIDs),
            nodeIDs: nodeIDs,
            inputIDs: inputIDs,
            weightedCoverage: affinityByInputID.values.reduce(0, +),
            affinityByInputID: affinityByInputID
        )
    }

    private func weightedJaccard(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        let keys = Set(lhs.keys).union(rhs.keys)
        guard !keys.isEmpty else {
            return 0
        }

        var intersection = 0.0
        var union = 0.0
        for key in keys {
            let lhsValue = lhs[key] ?? 0
            let rhsValue = rhs[key] ?? 0
            intersection += min(lhsValue, rhsValue)
            union += max(lhsValue, rhsValue)
        }

        guard union > 0 else {
            return 0
        }
        return intersection / union
    }

    private func compareWeightedClusters(_ lhs: WeightedGardenCluster, _ rhs: WeightedGardenCluster) -> Bool {
        if lhs.weightedCoverage != rhs.weightedCoverage {
            return lhs.weightedCoverage > rhs.weightedCoverage
        }
        if lhs.inputIDs.count != rhs.inputIDs.count {
            return lhs.inputIDs.count > rhs.inputIDs.count
        }
        if lhs.nodeIDs.count != rhs.nodeIDs.count {
            return lhs.nodeIDs.count < rhs.nodeIDs.count
        }
        return lhs.signature.rawValue < rhs.signature.rawValue
    }

    private func weightedCoverage(of cluster: GardenClusterSnapshot, index: GraphHierarchyIndex) -> Double {
        let inputIDs = Set(cluster.inputIDs)
        return inputIDs.reduce(into: 0.0) { partialResult, inputID in
            let affinities = index.targetAffinitiesByInputID[inputID] ?? [:]
            let clusterAffinity = cluster.nodeIDs.reduce(into: 0.0) { affinityResult, nodeID in
                affinityResult += affinities[nodeID] ?? 0
            }
            partialResult += clusterAffinity
        }
    }

    private func clusterNodeIDs(from clusterID: String) -> [String] {
        let parts = clusterID.split(separator: "|").map(String.init)
        if parts.count <= 1 {
            return [clusterID]
        }
        return parts
    }

    private func clusterMetrics(for inputs: [InputStatus]) -> ClusterMetrics {
        let activeInputs = inputs.filter(\.isActive)
        let activeCount = activeInputs.count
        let checkedTodayCount = activeInputs.filter(\.isCheckedToday).count

        let weeklyAverage: Double
        if activeInputs.isEmpty {
            weeklyAverage = 0
        } else {
            weeklyAverage = activeInputs.reduce(0) { partialResult, input in
                partialResult + input.completion
            } / Double(activeInputs.count)
        }

        let todayRatio: Double
        if activeInputs.isEmpty {
            todayRatio = 0
        } else {
            todayRatio = Double(checkedTodayCount) / Double(activeInputs.count)
        }

        let bloomLevel = min(1.0, max(0.0, (0.7 * todayRatio) + (0.3 * weeklyAverage)))
        return ClusterMetrics(
            activeCount: activeCount,
            checkedTodayCount: checkedTodayCount,
            bloomLevel: bloomLevel
        )
    }
}

private struct ClusterMetrics {
    let activeCount: Int
    let checkedTodayCount: Int
    let bloomLevel: Double
}

private struct GraphHierarchyIndex {
    let targetAffinitiesByInputID: [String: [String: Double]]
    let nodeLabelByID: [String: String]

    init(graphData: CausalGraphData, inputs: [InputStatus], nameResolver: GardenNameResolver) {
        let nodeByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data) })
        nodeLabelByID = graphData.nodes.reduce(into: [:]) { partialResult, node in
            partialResult[node.data.id] = nameResolver.nodeTitle(
                nodeID: node.data.id,
                fallbackLabel: node.data.label
            )
        }

        var affinityBySourceNodeByTargetNode: [String: [String: Double]] = [:]
        for edge in graphData.edges {
            guard edge.data.isDeactivated != true else {
                continue
            }
            guard let targetNode = nodeByID[edge.data.target] else {
                continue
            }
            guard targetNode.styleClass != "intervention" else {
                continue
            }
            guard targetNode.isDeactivated != true else {
                continue
            }

            let edgeAffinity = abs(Self.edgeStrength(edge.data)) * Self.evidenceFactor(edge.data, targetNode: targetNode)
            guard edgeAffinity > 0 else {
                continue
            }

            affinityBySourceNodeByTargetNode[edge.data.source, default: [:]][edge.data.target, default: 0] += edgeAffinity
        }

        targetAffinitiesByInputID = inputs.reduce(into: [:]) { partialResult, input in
            let sourceNodeID = input.graphNodeID ?? input.id
            partialResult[input.id] = affinityBySourceNodeByTargetNode[sourceNodeID] ?? [:]
        }
    }

    private static func edgeStrength(_ edge: GraphEdgeData) -> Double {
        if let explicitStrength = edge.strength {
            return min(1.0, max(-1.0, explicitStrength))
        }

        let normalizedEdgeType = edge.edgeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalizedEdgeType == "protective" || normalizedEdgeType == "inhibits" {
            return -0.6
        }
        if normalizedEdgeType == "feedback" {
            return 0.7
        }
        if normalizedEdgeType == "dashed" {
            return 0.45
        }
        if normalizedEdgeType == "causal" || normalizedEdgeType == "causes" || normalizedEdgeType == "triggers" || normalizedEdgeType == "forward" {
            return 0.8
        }

        if let label = edge.label?.lowercased() {
            if label.contains("strong") {
                return 0.9
            }
            if label.contains("weak") {
                return 0.4
            }
        }

        return 0.55
    }

    private static func evidenceFactor(_ edge: GraphEdgeData, targetNode: GraphNodeData) -> Double {
        let evidenceText = targetNode.tooltip?.evidence
            ?? edge.label
            ?? edge.tooltip
            ?? ""
        let normalized = evidenceText.lowercased()

        if normalized.contains("robust") || normalized.contains("strong") || normalized.contains("high") {
            return 1.0
        }
        if normalized.contains("moderate") || normalized.contains("medium") {
            return 0.75
        }
        if normalized.contains("preliminary") || normalized.contains("low") || normalized.contains("limited") {
            return 0.55
        }

        return 0.4
    }
}
