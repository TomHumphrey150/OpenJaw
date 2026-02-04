//
//  InterventionService.swift
//  Skywalker
//
//  OpenJaw - Persistence and CRUD for user interventions and completions
//

import Foundation
import Observation

@Observable
@MainActor
class InterventionService {
    var userInterventions: [UserIntervention] = []
    var completions: [InterventionCompletion] = []
    var decisions: [InterventionDecision] = []
    var reminderGroups: [ReminderGroup] = []

    private let catalogDataService: CatalogDataService
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var userInterventionsFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("user_interventions.json")
    }

    private var completionsFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("intervention_completions.json")
    }

    private var decisionsFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("intervention_decisions.json")
    }

    private var reminderGroupsFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("reminder_groups.json")
    }

    init(catalogDataService: CatalogDataService = CatalogDataService()) {
        self.catalogDataService = catalogDataService
        loadUserInterventions()
        loadCompletions()
        loadDecisions()
        loadReminderGroups()
    }

    // MARK: - User Interventions

    func addIntervention(_ interventionId: String) {
        guard !userInterventions.contains(where: { $0.interventionId == interventionId }) else {
            print("[InterventionService] Intervention \(interventionId) already added")
            return
        }

        let definition = catalogDataService.find(byId: interventionId)

        // Determine if reminders should be auto-enabled
        let shouldEnableReminder = definition?.isRemindable == true &&
                                   definition?.defaultReminderMinutes != nil

        var userIntervention = UserIntervention(
            interventionId: interventionId,
            reminderIntervalMinutes: definition?.defaultReminderMinutes
        )

        // Auto-enable reminder if the habit supports it
        if shouldEnableReminder {
            userIntervention.reminderEnabled = true
        }

        userInterventions.append(userIntervention)
        saveUserInterventions()
        print("[InterventionService] Added intervention: \(interventionId), reminder enabled: \(userIntervention.reminderEnabled)")
    }

    func removeIntervention(_ interventionId: String) {
        userInterventions.removeAll { $0.interventionId == interventionId }
        saveUserInterventions()
        print("[InterventionService] Removed intervention: \(interventionId)")
    }

    func toggleIntervention(_ interventionId: String) {
        if hasIntervention(interventionId) {
            removeIntervention(interventionId)
        } else {
            addIntervention(interventionId)
        }
    }

    func hasIntervention(_ interventionId: String) -> Bool {
        userInterventions.contains { $0.interventionId == interventionId && $0.isEnabled }
    }

    func updateIntervention(_ intervention: UserIntervention) {
        guard let index = userInterventions.firstIndex(where: { $0.id == intervention.id }) else {
            return
        }
        userInterventions[index] = intervention
        saveUserInterventions()
    }

    func enabledInterventions() -> [UserIntervention] {
        userInterventions.filter { $0.isEnabled }
    }

    func interventionDefinition(for userIntervention: UserIntervention) -> InterventionDefinition? {
        catalogDataService.find(byId: userIntervention.interventionId)
    }

    // MARK: - Completions

    func logCompletion(interventionId: String, value: CompletionValue, timestamp: Date = Date()) {
        let completion = InterventionCompletion(
            interventionId: interventionId,
            value: value,
            timestamp: timestamp
        )
        completions.append(completion)
        saveCompletions()
        print("[InterventionService] Logged completion for: \(interventionId)")
    }

    func removeLastCompletion(for interventionId: String) {
        // Find the most recent completion for this intervention
        if let lastIndex = completions.lastIndex(where: { $0.interventionId == interventionId }) {
            completions.remove(at: lastIndex)
            saveCompletions()
            print("[InterventionService] Removed last completion for: \(interventionId)")
        }
    }

    func todayCompletions(for interventionId: String) -> [InterventionCompletion] {
        completions(on: Date(), for: interventionId)
    }

    func completions(on day: Date, for interventionId: String) -> [InterventionCompletion] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: day)

        return completions.filter { completion in
            completion.interventionId == interventionId &&
            calendar.isDate(completion.timestamp, inSameDayAs: targetDay)
        }
    }

    func todayCompletionCount(for interventionId: String) -> Int {
        completionCount(on: Date(), for: interventionId)
    }

    func completionCount(on day: Date, for interventionId: String) -> Int {
        completions(on: day, for: interventionId).reduce(0) { total, completion in
            switch completion.value {
            case .count(let count):
                return total + count
            default:
                return total + 1
            }
        }
    }

    func isCompletedToday(_ interventionId: String) -> Bool {
        isCompleted(on: Date(), interventionId: interventionId)
    }

    func isCompleted(on day: Date, interventionId: String) -> Bool {
        !completions(on: day, for: interventionId).isEmpty
    }

    func completions(for interventionId: String, inLast days: Int) -> [InterventionCompletion] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }

        return completions.filter { completion in
            completion.interventionId == interventionId &&
            completion.timestamp >= startDate
        }
    }

    func clearCompletions(for interventionId: String) {
        completions.removeAll { $0.interventionId == interventionId }
        saveCompletions()
    }

    func clearAllCompletions() {
        completions.removeAll()
        saveCompletions()
        print("[InterventionService] Cleared all completions")
    }

    // MARK: - Decisions

    func decision(for interventionId: String, on day: Date) -> InterventionDecision? {
        let targetDay = Calendar.current.startOfDay(for: day)
        return decisions.first { decision in
            decision.interventionId == interventionId &&
            Calendar.current.isDate(decision.day, inSameDayAs: targetDay)
        }
    }

    func decisionStatus(for interventionId: String, on day: Date) -> InterventionDecisionStatus? {
        decision(for: interventionId, on: day)?.status
    }

    func setDecision(
        interventionId: String,
        on day: Date,
        status: InterventionDecisionStatus,
        count: Int? = nil
    ) {
        let targetDay = Calendar.current.startOfDay(for: day)

        if let index = decisions.firstIndex(where: {
            $0.interventionId == interventionId &&
            Calendar.current.isDate($0.day, inSameDayAs: targetDay)
        }) {
            decisions[index].status = status
            decisions[index].count = count
            decisions[index].updatedAt = Date()
        } else {
            let decision = InterventionDecision(
                interventionId: interventionId,
                day: targetDay,
                status: status,
                count: count
            )
            decisions.append(decision)
        }

        saveDecisions()
    }

    func applyDecision(
        for definition: InterventionDefinition,
        on day: Date,
        status: InterventionDecisionStatus,
        count: Int? = nil
    ) {
        let targetDay = Calendar.current.startOfDay(for: day)
        setDecision(interventionId: definition.id, on: targetDay, status: status, count: count)

        guard status == .done else {
            return
        }

        if isCompleted(on: targetDay, interventionId: definition.id) {
            return
        }

        let completionValue: CompletionValue
        switch definition.trackingType {
        case .counter:
            let total = max(count ?? 1, 1)
            completionValue = .count(total)
        case .timer:
            completionValue = .duration(0)
        case .checklist:
            completionValue = .checklist([:])
        case .appointment, .automatic, .binary:
            completionValue = .binary(true)
        }

        let timestamp = Calendar.current.date(byAdding: .hour, value: 12, to: targetDay) ?? targetDay
        logCompletion(interventionId: definition.id, value: completionValue, timestamp: timestamp)
    }

    // MARK: - Streak Calculation

    /// Calculate current streak for a habit (consecutive days including today)
    /// Returns 0 if not completed today, 1+ if streak exists
    func currentStreak(for interventionId: String) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Check if completed today first
        guard isCompletedToday(interventionId) else {
            return 0
        }

        // Count consecutive days backwards from today
        var streakCount = 1
        var checkDate = today

        while true {
            // Move to previous day
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                break
            }
            checkDate = previousDay

            // Check if there's a completion on that day
            let hasCompletion = completions.contains { completion in
                completion.interventionId == interventionId &&
                calendar.isDate(completion.timestamp, inSameDayAs: checkDate)
            }

            if hasCompletion {
                streakCount += 1
            } else {
                break
            }
        }

        return streakCount
    }

    // MARK: - Reminder Groups

    /// Create a new reminder group with the given interventions
    @discardableResult
    func createGroup(
        name: String,
        interventionIds: [String],
        intervalMinutes: Int
    ) -> ReminderGroup {
        // Remove interventions from any existing groups first
        for id in interventionIds {
            removeFromGroup(id)
        }

        let group = ReminderGroup(
            name: name,
            interventionIds: interventionIds,
            intervalMinutes: intervalMinutes
        )

        reminderGroups.append(group)

        // Update all member interventions to reference this group
        for id in interventionIds {
            if let index = userInterventions.firstIndex(where: { $0.interventionId == id }) {
                userInterventions[index].reminderGroupId = group.id
            }
        }

        saveReminderGroups()
        saveUserInterventions()
        print("[InterventionService] Created group '\(name)' with \(interventionIds.count) members")
        return group
    }

    /// Add an intervention to an existing group
    func addToGroup(_ interventionId: String, groupId: UUID) {
        guard let groupIndex = reminderGroups.firstIndex(where: { $0.id == groupId }) else {
            print("[InterventionService] Group \(groupId) not found")
            return
        }

        // Remove from any existing group first
        removeFromGroup(interventionId)

        // Add to the new group
        reminderGroups[groupIndex].interventionIds.append(interventionId)

        // Update intervention to reference this group
        if let intIndex = userInterventions.firstIndex(where: { $0.interventionId == interventionId }) {
            userInterventions[intIndex].reminderGroupId = groupId
        }

        saveReminderGroups()
        saveUserInterventions()
        print("[InterventionService] Added \(interventionId) to group \(groupId)")
    }

    /// Remove an intervention from its group
    func removeFromGroup(_ interventionId: String) {
        // Find which group contains this intervention
        guard let groupIndex = reminderGroups.firstIndex(where: { $0.contains(interventionId) }) else {
            return
        }

        let groupId = reminderGroups[groupIndex].id

        // Remove from group's intervention list
        reminderGroups[groupIndex].interventionIds.removeAll { $0 == interventionId }

        // Clear the group reference from intervention
        if let intIndex = userInterventions.firstIndex(where: { $0.interventionId == interventionId }) {
            userInterventions[intIndex].reminderGroupId = nil
        }

        // If group now has 0 or 1 members, dissolve it
        if reminderGroups[groupIndex].interventionIds.count <= 1 {
            // Clear group reference from remaining member if any
            if let remainingId = reminderGroups[groupIndex].interventionIds.first,
               let intIndex = userInterventions.firstIndex(where: { $0.interventionId == remainingId }) {
                userInterventions[intIndex].reminderGroupId = nil
            }
            reminderGroups.remove(at: groupIndex)
            print("[InterventionService] Dissolved group \(groupId)")
        }

        saveReminderGroups()
        saveUserInterventions()
        print("[InterventionService] Removed \(interventionId) from group")
    }

    /// Get the group that contains a specific intervention
    func getGroup(for interventionId: String) -> ReminderGroup? {
        reminderGroups.first { $0.contains(interventionId) }
    }

    /// Get all definitions for interventions in a group
    func definitions(for group: ReminderGroup) -> [InterventionDefinition] {
        group.interventionIds.compactMap { catalogDataService.find(byId: $0) }
    }

    /// Update a reminder group
    func updateGroup(_ group: ReminderGroup) {
        guard let index = reminderGroups.firstIndex(where: { $0.id == group.id }) else {
            return
        }
        reminderGroups[index] = group
        saveReminderGroups()
    }

    // MARK: - Persistence

    private func saveUserInterventions() {
        do {
            let data = try encoder.encode(userInterventions)
            try data.write(to: userInterventionsFileURL, options: .atomic)
            print("[InterventionService] Saved \(userInterventions.count) user interventions")
        } catch {
            print("[InterventionService] Failed to save user interventions: \(error.localizedDescription)")
        }
    }

    private func loadUserInterventions() {
        guard fileManager.fileExists(atPath: userInterventionsFileURL.path) else {
            print("[InterventionService] No user interventions file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: userInterventionsFileURL)
            userInterventions = try decoder.decode([UserIntervention].self, from: data)
            print("[InterventionService] Loaded \(userInterventions.count) user interventions")
        } catch {
            print("[InterventionService] Failed to load user interventions: \(error.localizedDescription)")
            userInterventions = []
        }
    }

    private func saveCompletions() {
        do {
            let data = try encoder.encode(completions)
            try data.write(to: completionsFileURL, options: .atomic)
            print("[InterventionService] Saved \(completions.count) completions")
        } catch {
            print("[InterventionService] Failed to save completions: \(error.localizedDescription)")
        }
    }

    private func saveDecisions() {
        do {
            let data = try encoder.encode(decisions)
            try data.write(to: decisionsFileURL, options: .atomic)
            print("[InterventionService] Saved \(decisions.count) decisions")
        } catch {
            print("[InterventionService] Failed to save decisions: \(error.localizedDescription)")
        }
    }

    private func loadCompletions() {
        guard fileManager.fileExists(atPath: completionsFileURL.path) else {
            print("[InterventionService] No completions file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: completionsFileURL)
            completions = try decoder.decode([InterventionCompletion].self, from: data)
            print("[InterventionService] Loaded \(completions.count) completions")
        } catch {
            print("[InterventionService] Failed to load completions: \(error.localizedDescription)")
            completions = []
        }
    }

    private func loadDecisions() {
        guard fileManager.fileExists(atPath: decisionsFileURL.path) else {
            print("[InterventionService] No decisions file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: decisionsFileURL)
            decisions = try decoder.decode([InterventionDecision].self, from: data)
            print("[InterventionService] Loaded \(decisions.count) decisions")
        } catch {
            print("[InterventionService] Failed to load decisions: \(error.localizedDescription)")
            decisions = []
        }
    }

    private func saveReminderGroups() {
        do {
            let data = try encoder.encode(reminderGroups)
            try data.write(to: reminderGroupsFileURL, options: .atomic)
            print("[InterventionService] Saved \(reminderGroups.count) reminder groups")
        } catch {
            print("[InterventionService] Failed to save reminder groups: \(error.localizedDescription)")
        }
    }

    private func loadReminderGroups() {
        guard fileManager.fileExists(atPath: reminderGroupsFileURL.path) else {
            print("[InterventionService] No reminder groups file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: reminderGroupsFileURL)
            reminderGroups = try decoder.decode([ReminderGroup].self, from: data)
            print("[InterventionService] Loaded \(reminderGroups.count) reminder groups")
        } catch {
            print("[InterventionService] Failed to load reminder groups: \(error.localizedDescription)")
            reminderGroups = []
        }
    }

    // MARK: - Reset Functions

    /// Resets intervention scores (completions and decisions) but keeps the plan (habits) intact.
    /// Does NOT touch UserDefaults.
    func resetScores() {
        print("[InterventionService] Resetting scores...")

        // Clear completions and decisions only
        completions.removeAll()
        decisions.removeAll()

        // Delete the score files
        let filesToDelete = [
            completionsFileURL,
            decisionsFileURL
        ]

        for url in filesToDelete {
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    print("[InterventionService] Deleted: \(url.lastPathComponent)")
                }
            } catch {
                print("[InterventionService] Failed to delete \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        print("[InterventionService] Scores reset complete")
    }

    /// Resets the entire plan: removes all habits, completions, decisions, and reminder groups.
    /// Does NOT touch UserDefaults (progress scores, section orders, etc.).
    func resetPlan() {
        print("[InterventionService] Resetting plan...")

        // Clear all in-memory data
        userInterventions.removeAll()
        completions.removeAll()
        decisions.removeAll()
        reminderGroups.removeAll()

        // Delete all JSON files
        let filesToDelete = [
            userInterventionsFileURL,
            completionsFileURL,
            decisionsFileURL,
            reminderGroupsFileURL
        ]

        for url in filesToDelete {
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    print("[InterventionService] Deleted: \(url.lastPathComponent)")
                }
            } catch {
                print("[InterventionService] Failed to delete \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        print("[InterventionService] Plan reset complete")
    }
}
