protocol DashboardRepository {
    func loadDashboardSnapshot() -> DashboardSnapshot
}

struct InMemoryDashboardRepository: DashboardRepository {
    func loadDashboardSnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            outcomes: OutcomeSummary(
                shieldScore: 38,
                burdenTrendPercent: -11,
                topContributor: "Reflux pathway",
                confidence: "Moderate",
                burdenProgress: 0.66
            ),
            situation: SituationSummary(
                focusedNode: "RMMA",
                tier: "Tier 7",
                visibleHotspots: 3,
                topSource: "Reflux pathway"
            ),
            inputs: [
                InputStatus(id: "ppi", name: "PPI", statusText: "Checked", completion: 0.90),
                InputStatus(id: "reflux_diet", name: "Reflux Diet", statusText: "Checked", completion: 0.76),
                InputStatus(id: "bed_elevation", name: "Bed Elevation", statusText: "1/7", completion: 0.30),
            ]
        )
    }
}
