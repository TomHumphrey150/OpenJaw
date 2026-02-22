import Foundation

extension CausalGraphData {
    static let defaultGraph = CausalGraphData(
        nodes: [
            GraphNodeElement(data: GraphNodeData(id: "STRESS", label: "Stress & Anxiety\nOR 2.07", styleClass: "moderate", confirmed: "yes", tier: 2, tooltip: GraphTooltip(evidence: "Moderate", stat: "OR 2.07", citation: "Chemelo 2020", mechanism: "Stress increases cortisol and arousal"))),
            GraphNodeElement(data: GraphNodeData(id: "GERD", label: "GERD / Silent Reflux\nOR 6.87", styleClass: "robust", confirmed: "yes", tier: 3, tooltip: GraphTooltip(evidence: "Robust", stat: "OR 6.87", citation: "Li 2018", mechanism: "Acid exposure can trigger microarousal"))),
            GraphNodeElement(data: GraphNodeData(id: "SLEEP_DEP", label: "Sleep Deprivation", styleClass: "moderate", confirmed: "yes", tier: 2, tooltip: GraphTooltip(evidence: "Moderate", stat: "Dose-dependent", citation: "Sleep studies", mechanism: "Fragmented sleep increases arousal"))),
            GraphNodeElement(data: GraphNodeData(id: "MICRO", label: "Microarousal\n79% precede RMMA", styleClass: "robust", confirmed: "yes", tier: 6, tooltip: GraphTooltip(evidence: "Robust", stat: "79%", citation: "Kato 2001", mechanism: "Microarousal is upstream of RMMA"))),
            GraphNodeElement(data: GraphNodeData(id: "RMMA", label: "RMMA / Sleep Bruxism", styleClass: "robust", confirmed: "yes", tier: 7, tooltip: GraphTooltip(evidence: "Robust", stat: "Replicated", citation: "Kato 2003", mechanism: "Central motor event"))),
            GraphNodeElement(data: GraphNodeData(id: "NECK_TIGHTNESS", label: "Neck Tightness\n& Spasm", styleClass: "symptom", confirmed: "yes", tier: 10, tooltip: GraphTooltip(evidence: "Symptom", stat: nil, citation: "Clinical", mechanism: "Downstream symptom burden"))),
            GraphNodeElement(data: GraphNodeData(id: "PPI_TX", label: "PPI / Lansoprazole", styleClass: "intervention", confirmed: nil, tier: nil, tooltip: GraphTooltip(evidence: "Robust", stat: "RCT", citation: "Ohmure 2016", mechanism: "Reduces acid production"))),
        ],
        edges: [
            GraphEdgeElement(data: GraphEdgeData(source: "STRESS", target: "SLEEP_DEP", label: "hyperarousal", edgeType: "forward", edgeColor: "#b45309", tooltip: "Stress can worsen sleep deprivation")),
            GraphEdgeElement(data: GraphEdgeData(source: "STRESS", target: "GERD", label: "visceral hypersens.", edgeType: "forward", edgeColor: "#b45309", tooltip: "Stress can increase reflux sensitivity")),
            GraphEdgeElement(data: GraphEdgeData(source: "GERD", target: "MICRO", label: nil, edgeType: "forward", edgeColor: "#1b4332", tooltip: "Reflux can contribute to microarousal")),
            GraphEdgeElement(data: GraphEdgeData(source: "SLEEP_DEP", target: "MICRO", label: nil, edgeType: "forward", edgeColor: "#b45309", tooltip: "Sleep debt increases microarousal")),
            GraphEdgeElement(data: GraphEdgeData(source: "MICRO", target: "RMMA", label: "79% precede", edgeType: "forward", edgeColor: "#1b4332", tooltip: "Microarousal precedes RMMA")),
            GraphEdgeElement(data: GraphEdgeData(source: "RMMA", target: "NECK_TIGHTNESS", label: nil, edgeType: "dashed", edgeColor: "#1e3a5f", tooltip: "RMMA may worsen neck tightness")),
            GraphEdgeElement(data: GraphEdgeData(source: "PPI_TX", target: "GERD", label: nil, edgeType: "forward", edgeColor: "#065f46", tooltip: "Intervention reduces reflux burden")),
        ]
    )
}

extension UserDataDocument {
    static let mockForUI = UserDataDocument(
        version: 1,
        lastExport: nil,
        personalStudies: [],
        notes: [],
        experiments: [],
        interventionRatings: [
            InterventionRating(interventionId: "PPI_TX", effectiveness: "effective", notes: "Helpful in week 2", lastUpdated: "2026-02-20T08:00:00.000Z")
        ],
        dailyCheckIns: [
            "2026-02-21": ["PPI_TX", "REFLUX_DIET_TX"],
            "2026-02-20": ["PPI_TX"],
            "2026-02-19": ["PPI_TX", "BED_ELEV_TX"],
        ],
        nightExposures: [],
        nightOutcomes: [
            NightOutcome(nightId: "2026-02-21", microArousalCount: 11, microArousalRatePerHour: 2.1, confidence: 0.73, totalSleepMinutes: 402, source: "wearable", createdAt: "2026-02-21T07:40:00.000Z"),
            NightOutcome(nightId: "2026-02-20", microArousalCount: 14, microArousalRatePerHour: 2.8, confidence: 0.69, totalSleepMinutes: 389, source: "wearable", createdAt: "2026-02-20T07:35:00.000Z"),
        ],
        morningStates: [
            MorningState(nightId: "2026-02-21", globalSensation: 6, neckTightness: 4, jawSoreness: 3, earFullness: 2, healthAnxiety: 3, createdAt: "2026-02-21T08:10:00.000Z")
        ],
        habitTrials: [],
        habitClassifications: [
            HabitClassification(interventionId: "PPI_TX", status: .helpful, nightsOn: 5, nightsOff: 5, microArousalDeltaPct: -18, morningStateDelta: -1.1, windowQuality: .cleanOneVariable, updatedAt: "2026-02-21T08:15:00.000Z")
        ],
        activeInterventions: ["PPI_TX", "REFLUX_DIET_TX", "BED_ELEV_TX"],
        hiddenInterventions: [],
        unlockedAchievements: [],
        customCausalDiagram: CustomCausalDiagram(graphData: .defaultGraph, lastModified: "2026-02-21T08:10:00.000Z"),
        experienceFlow: ExperienceFlow(
            hasCompletedInitialGuidedFlow: true,
            lastGuidedEntryDate: "2026-02-20",
            lastGuidedCompletedDate: "2026-02-20",
            lastGuidedStatus: .completed
        )
    )
}
