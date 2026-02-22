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
            outcomesMetadata: .empty,
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
                    trackingMode: .binary,
                    statusText: "Checked today",
                    completion: 0.90,
                    isCheckedToday: true,
                    doseState: nil,
                    graphNodeID: nil,
                    classificationText: "Helpful",
                    isHidden: false,
                    evidenceLevel: nil,
                    evidenceSummary: nil,
                    detailedDescription: nil,
                    citationIDs: [],
                    externalLink: nil
                ),
                InputStatus(
                    id: "reflux_diet",
                    name: "Reflux Diet",
                    trackingMode: .binary,
                    statusText: "Checked today",
                    completion: 0.76,
                    isCheckedToday: true,
                    doseState: nil,
                    graphNodeID: nil,
                    classificationText: nil,
                    isHidden: false,
                    evidenceLevel: nil,
                    evidenceSummary: nil,
                    detailedDescription: nil,
                    citationIDs: [],
                    externalLink: nil
                ),
                InputStatus(
                    id: "bed_elevation",
                    name: "Bed Elevation",
                    trackingMode: .binary,
                    statusText: "1/7 days",
                    completion: 0.30,
                    isCheckedToday: false,
                    doseState: nil,
                    graphNodeID: nil,
                    classificationText: nil,
                    isHidden: false,
                    evidenceLevel: nil,
                    evidenceSummary: nil,
                    detailedDescription: nil,
                    citationIDs: [],
                    externalLink: nil
                ),
            ]
        )
    }
}
