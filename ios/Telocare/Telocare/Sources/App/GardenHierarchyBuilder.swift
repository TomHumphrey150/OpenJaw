import Foundation

struct GardenHierarchyBuilder {
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
        let index = GraphHierarchyIndex(graphData: graphData, inputs: inputs, nameResolver: nameResolver)

        var currentInputs = inputs
        var resolvedNodePath: [String] = []
        var excludedNodeIDs = Set<String>()
        var levels: [GardenHierarchyLevel] = []
        var branchRootNodeID: String?

        while true {
            let clusters = buildClusters(
                currentInputs: currentInputs,
                excludedNodeIDs: excludedNodeIDs,
                index: index,
                branchRootNodeID: branchRootNodeID
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
            excludedNodeIDs.insert(selectedNodeID)
            if branchRootNodeID == nil {
                branchRootNodeID = selectedNodeID
            }
        }

        return GardenHierarchyBuildResult(
            filteredInputs: currentInputs,
            levels: levels,
            resolvedNodePath: resolvedNodePath
        )
    }

    func nodeTitle(
        for nodeID: String,
        in graphData: CausalGraphData
    ) -> String {
        let labelByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data.label) })
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
        let title = nameResolver.layerTitle(nodePath: nodePath, labelByID: labelByID)
        let branchRootNodeID = nodePath.first

        return GardenClusterSnapshot(
            nodeID: currentNodeID,
            title: title,
            inputIDs: filteredInputs.map(\.id),
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
        branchRootNodeID: String?
    ) -> [GardenClusterSnapshot] {
        var groupedInputsByNodeID: [String: [InputStatus]] = [:]

        for input in currentInputs {
            let nodeIDs = index.targetNodeIDsByInputID[input.id] ?? []
            for nodeID in nodeIDs where !excludedNodeIDs.contains(nodeID) {
                groupedInputsByNodeID[nodeID, default: []].append(input)
            }
        }

        return groupedInputsByNodeID.compactMap { nodeID, groupedInputs in
            guard !groupedInputs.isEmpty else {
                return nil
            }
            guard groupedInputs.count < currentInputs.count else {
                return nil
            }

            let metrics = clusterMetrics(for: groupedInputs)
            return GardenClusterSnapshot(
                nodeID: nodeID,
                title: index.nodeTitleByID[nodeID] ?? nodeID,
                inputIDs: groupedInputs.map(\.id),
                activeCount: metrics.activeCount,
                checkedTodayCount: metrics.checkedTodayCount,
                bloomLevel: metrics.bloomLevel,
                themeKey: themeResolver.themeForCluster(nodeID: nodeID, branchRootNodeID: branchRootNodeID)
            )
        }
        .sorted { lhs, rhs in
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
    let targetNodeIDsByInputID: [String: [String]]
    let nodeTitleByID: [String: String]

    init(graphData: CausalGraphData, inputs: [InputStatus], nameResolver: GardenNameResolver) {
        let nodeByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.data.id, $0.data) })
        nodeTitleByID = graphData.nodes.reduce(into: [:]) { partialResult, node in
            partialResult[node.data.id] = nameResolver.nodeTitle(
                nodeID: node.data.id,
                fallbackLabel: node.data.label
            )
        }

        let targetIDsBySourceID = graphData.edges.reduce(into: [String: [String]]()) { partialResult, edge in
            guard edge.data.isDeactivated != true else {
                return
            }
            guard let targetNode = nodeByID[edge.data.target] else {
                return
            }
            guard targetNode.styleClass != "intervention" else {
                return
            }
            guard targetNode.isDeactivated != true else {
                return
            }

            partialResult[edge.data.source, default: []].append(edge.data.target)
        }

        targetNodeIDsByInputID = inputs.reduce(into: [:]) { partialResult, input in
            let sourceNodeID = input.graphNodeID ?? input.id
            let targetNodeIDs = targetIDsBySourceID[sourceNodeID] ?? []
            if targetNodeIDs.isEmpty {
                partialResult[input.id] = []
                return
            }

            var seenNodeIDs = Set<String>()
            let uniqueTargetNodeIDs = targetNodeIDs.filter { seenNodeIDs.insert($0).inserted }
            partialResult[input.id] = uniqueTargetNodeIDs
        }
    }
}
