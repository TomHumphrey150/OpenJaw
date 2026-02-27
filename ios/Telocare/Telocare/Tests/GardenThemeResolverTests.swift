import Testing
@testable import Telocare

struct GardenThemeResolverTests {
    private let resolver = GardenThemeResolver()

    @Test func rootThemeAssignmentIsDeterministic() {
        let first = resolver.themeForRoot(nodeID: "STRESS")
        let second = resolver.themeForRoot(nodeID: "STRESS")
        #expect(first == second)
    }

    @Test func descendantsInheritBranchRootTheme() {
        let branchTheme = resolver.themeForCluster(nodeID: "STRESS", branchRootNodeID: nil)
        let childTheme = resolver.themeForCluster(nodeID: "SLEEP_DEP", branchRootNodeID: "STRESS")
        let deepChildTheme = resolver.themeForCluster(nodeID: "MICRO", branchRootNodeID: "STRESS")

        #expect(childTheme == branchTheme)
        #expect(deepChildTheme == branchTheme)
    }

    @Test func clusterWithoutBranchUsesOwnTheme() {
        let stressTheme = resolver.themeForCluster(nodeID: "STRESS", branchRootNodeID: nil)
        let gerdTheme = resolver.themeForCluster(nodeID: "GERD", branchRootNodeID: nil)
        #expect(stressTheme == resolver.themeForRoot(nodeID: "STRESS"))
        #expect(gerdTheme == resolver.themeForRoot(nodeID: "GERD"))
    }

    @Test func branchThemeRemainsStableAcrossBackAndForward() {
        let forward = resolver.themeForCluster(nodeID: "MICRO", branchRootNodeID: "STRESS")
        let backToParent = resolver.themeForCluster(nodeID: "SLEEP_DEP", branchRootNodeID: "STRESS")
        let forwardAgain = resolver.themeForCluster(nodeID: "MICRO", branchRootNodeID: "STRESS")

        #expect(forward == backToParent)
        #expect(forwardAgain == forward)
    }
}
