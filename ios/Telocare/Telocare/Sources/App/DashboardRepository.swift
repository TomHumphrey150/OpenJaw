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
            outcomeRecords: [
                OutcomeRecord(
                    id: "2026-02-21",
                    microArousalRatePerHour: 2.1,
                    microArousalCount: 11,
                    confidence: 0.73,
                    source: "wearable"
                ),
                OutcomeRecord(
                    id: "2026-02-20",
                    microArousalRatePerHour: 2.8,
                    microArousalCount: 14,
                    confidence: 0.69,
                    source: "wearable"
                ),
            ],
            situation: SituationSummary(
                focusedNode: "RMMA",
                tier: "Tier 7",
                visibleHotspots: 3,
                topSource: "Reflux pathway"
            ),
            inputs: [
                InputStatus(
                    id: "ppi",
                    name: "PPI",
                    statusText: "Checked today",
                    completion: 0.90,
                    isCheckedToday: true,
                    classificationText: "Helpful",
                    isHidden: false
                ),
                InputStatus(
                    id: "reflux_diet",
                    name: "Reflux Diet",
                    statusText: "Checked today",
                    completion: 0.76,
                    isCheckedToday: true,
                    classificationText: nil,
                    isHidden: false
                ),
                InputStatus(
                    id: "bed_elevation",
                    name: "Bed Elevation",
                    statusText: "1/7 days",
                    completion: 0.30,
                    isCheckedToday: false,
                    classificationText: nil,
                    isHidden: false
                ),
            ]
        )
    }
}
