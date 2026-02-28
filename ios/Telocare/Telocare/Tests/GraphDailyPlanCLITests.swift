import Foundation
import Testing
@testable import Telocare

struct GraphDailyPlanCLITests {
    @Test func generateDailyPlanReportFromFixture() throws {
        let environment = ProcessInfo.processInfo.environment
        let configPath = environment["TELOCARE_DAILY_PLAN_CONFIG_PATH"] ?? "/tmp/telocare-daily-plan-config.json"
        guard FileManager.default.fileExists(atPath: configPath) else {
            return
        }

        let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let config = try JSONDecoder().decode(DailyPlanCLIConfig.self, from: configData)
        let rowObject = try Self.readJSONObject(atPath: config.inputPath)
        let catalogObject = try Self.readJSONObject(atPath: config.catalogPath)

        let userID = rowObject["user_id"] as? String ?? "(unknown)"
        let updatedAt = rowObject["updated_at"] as? String
        let storeObject = try #require(rowObject["data"])
        let storeData = try JSONSerialization.data(withJSONObject: storeObject, options: [])
        let document = try JSONDecoder().decode(UserDataDocument.self, from: storeData)

        let catalogPayload = try #require(catalogObject["data"])
        let catalogData = try JSONSerialization.data(withJSONObject: catalogPayload, options: [])
        let interventionsCatalog = try JSONDecoder().decode(InterventionsCatalog.self, from: catalogData)

        let firstPartyContent = FirstPartyContentBundle(
            graphData: nil,
            interventionsCatalog: interventionsCatalog,
            outcomesMetadata: .empty,
            foundationCatalog: nil,
            planningPolicy: nil
        )
        let snapshot = DashboardSnapshotBuilder().build(
            from: document,
            firstPartyContent: firstPartyContent
        )
        let graphData = document.customCausalDiagram?.graphData ?? CanonicalGraphLoader.loadGraphOrFallback()
        let resolver = HabitPlanningMetadataResolver()
        let metadataByInterventionID = resolver.metadataByInterventionID(for: snapshot.inputs)
        let ladderByInterventionID = resolver.ladderByInterventionID(
            metadataByInterventionID: metadataByInterventionID
        )
        let planner = DailyPlanner()
        let flareDetector = FlareDetectionService()
        let mode = config.mode == .flare ? PlanningMode.flare : PlanningMode.baseline
        let planningPolicy = PlanningPolicy.default
        let todayKey = Self.localDateKey(from: Date())

        let proposal = planner.buildProposal(
            context: DailyPlanningContext(
                availableMinutes: max(10, config.availableMinutes),
                mode: mode,
                todayKey: todayKey,
                policy: planningPolicy,
                inputs: snapshot.inputs,
                planningMetadataByInterventionID: metadataByInterventionID,
                ladderByInterventionID: ladderByInterventionID,
                plannerState: document.habitPlannerState ?? .empty,
                morningStates: document.morningStates,
                nightOutcomes: document.nightOutcomes,
                selectedSlotStartMinutes: []
            )
        )

        let flareSuggestion = flareDetector.detectSuggestion(
            mode: mode,
            morningStates: document.morningStates,
            nightOutcomes: document.nightOutcomes,
            sensitivity: document.plannerPreferencesState?.flareSensitivity ?? .balanced
        )

        let report = DailyPlanCLIReport(
            userID: userID,
            rowUpdatedAt: updatedAt,
            graphVersion: document.customCausalDiagram?.graphVersion,
            mode: mode.rawValue,
            availableMinutes: proposal.availableMinutes,
            usedMinutes: proposal.usedMinutes,
            actionCount: proposal.actions.count,
            warnings: proposal.warnings,
            actions: proposal.actions.map { action in
                DailyPlanActionReport(
                    interventionID: action.interventionID,
                    title: action.title,
                    pillars: action.pillars.map { $0.rawValue },
                    tags: action.tags.map { $0.rawValue },
                    rungID: action.selectedRung.id,
                    estimatedMinutes: action.estimatedMinutes,
                    priorityClass: action.priorityClass,
                    priorityScore: action.priorityScore,
                    rationale: action.rationale
                )
            },
            flareSuggestion: flareSuggestion.map { suggestion in
                DailyPlanFlareSuggestionReport(
                    direction: suggestion.direction.rawValue,
                    reason: suggestion.reason,
                    snapshots: suggestion.snapshots.map { snapshot in
                        DailyPlanFlareSnapshotReport(
                            dayKey: snapshot.dayKey,
                            normalizedSymptomIndex: snapshot.normalizedSymptomIndex
                        )
                    }
                )
            },
            generatedAt: DateKeying.timestamp(from: Date()),
            topLevelClusterCount: GardenHierarchyBuilder().build(
                inputs: snapshot.inputs.filter(\.isActive),
                graphData: graphData,
                selection: .all
            ).levels.first?.clusters.count ?? 0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputData = try encoder.encode(report)
        try outputData.write(
            to: URL(fileURLWithPath: config.reportPath),
            options: Data.WritingOptions.atomic
        )
    }

    private static func readJSONObject(atPath path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try #require(raw as? [String: Any])
    }

    private static func localDateKey(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private struct DailyPlanCLIConfig: Codable {
    enum Mode: String, Codable {
        case baseline
        case flare
    }

    let inputPath: String
    let catalogPath: String
    let reportPath: String
    let availableMinutes: Int
    let mode: Mode
}

private struct DailyPlanCLIReport: Codable {
    let userID: String
    let rowUpdatedAt: String?
    let graphVersion: String?
    let mode: String
    let availableMinutes: Int
    let usedMinutes: Int
    let actionCount: Int
    let warnings: [String]
    let actions: [DailyPlanActionReport]
    let flareSuggestion: DailyPlanFlareSuggestionReport?
    let generatedAt: String
    let topLevelClusterCount: Int
}

private struct DailyPlanActionReport: Codable {
    let interventionID: String
    let title: String
    let pillars: [String]
    let tags: [String]
    let rungID: String
    let estimatedMinutes: Int
    let priorityClass: Int
    let priorityScore: Double
    let rationale: String
}

private struct DailyPlanFlareSuggestionReport: Codable {
    let direction: String
    let reason: String
    let snapshots: [DailyPlanFlareSnapshotReport]
}

private struct DailyPlanFlareSnapshotReport: Codable {
    let dayKey: String
    let normalizedSymptomIndex: Double
}
