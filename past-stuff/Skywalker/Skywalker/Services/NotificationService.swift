//
//  NotificationService.swift
//  Skywalker
//
//  OpenJaw - Local notification scheduling for intervention reminders
//

import Foundation
import UserNotifications
import Observation

@Observable
@MainActor
class NotificationService: NSObject {
    var isAuthorized = false
    var authorizationError: String?

    private let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if !granted {
                authorizationError = "Notification permission denied"
            }
            print("[NotificationService] Authorization granted: \(granted)")
        } catch {
            isAuthorized = false
            authorizationError = error.localizedDescription
            print("[NotificationService] Authorization error: \(error.localizedDescription)")
        }
    }

    private func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Scheduling

    /// Special interval values
    static let weekdaysOnly = -5

    func scheduleReminder(
        for intervention: InterventionDefinition,
        intervalMinutes: Int,
        hour: Int = 18,
        minute: Int = 0,
        weekday: Int = 1,
        quietHoursStart: Int = 22,  // 10 PM
        quietHoursEnd: Int = 8       // 8 AM
    ) async {
        if !isAuthorized {
            await requestAuthorization()
            if !isAuthorized { return }
        }

        // Remove existing notifications for this intervention
        await cancelReminder(for: intervention.id)

        let identifier = "intervention_\(intervention.id)"

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = intervention.name
        content.body = reminderMessage(for: intervention)
        content.sound = .default
        content.categoryIdentifier = "INTERVENTION_REMINDER"

        // Handle different interval types
        if intervalMinutes == Self.weekdaysOnly {
            // Weekdays only - schedule Mon-Fri at user-selected time
            await scheduleWeekdayReminders(identifier: identifier, content: content, hour: hour, minute: minute)
            print("[NotificationService] Scheduled weekday reminders for \(intervention.name) at \(hour):\(minute)")
        } else if intervalMinutes >= 10080 {
            // Weekly - schedule on user-selected day at user-selected time
            await scheduleWeeklyReminder(identifier: identifier, content: content, hour: hour, minute: minute, weekday: weekday)
            print("[NotificationService] Scheduled weekly reminder for \(intervention.name) on day \(weekday) at \(hour):\(minute)")
        } else if intervalMinutes >= 1440 {
            // Daily - schedule once per day at user-selected time
            await scheduleDailyReminder(identifier: identifier, content: content, hour: hour, minute: minute)
            print("[NotificationService] Scheduled daily reminder for \(intervention.name) at \(hour):\(minute)")
        } else {
            // Daytime awareness reminders - schedule throughout the day
            await scheduleDaytimeReminders(
                identifier: identifier,
                content: content,
                intervalMinutes: intervalMinutes,
                quietHoursStart: quietHoursStart,
                quietHoursEnd: quietHoursEnd
            )
            print("[NotificationService] Scheduled reminders for \(intervention.name) every \(intervalMinutes) min")
        }
    }

    /// Schedule a single daily reminder at user-selected time
    private func scheduleDailyReminder(identifier: String, content: UNMutableNotificationContent, hour: Int, minute: Int) async {
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(identifier)_daily",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("[NotificationService] Failed to schedule daily: \(error.localizedDescription)")
        }
    }

    /// Schedule reminders for weekdays (Mon-Fri) at user-selected time
    private func scheduleWeekdayReminders(identifier: String, content: UNMutableNotificationContent, hour: Int, minute: Int) async {
        // Weekday values: 1 = Sunday, 2 = Monday, ..., 6 = Friday, 7 = Saturday
        let weekdays = [2, 3, 4, 5, 6]  // Monday through Friday

        for weekday in weekdays {
            var dateComponents = DateComponents()
            dateComponents.weekday = weekday
            dateComponents.hour = hour
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(identifier)_weekday_\(weekday)",
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                print("[NotificationService] Failed to schedule weekday \(weekday): \(error.localizedDescription)")
            }
        }
    }

    /// Schedule a single weekly reminder on user-selected day at user-selected time
    private func scheduleWeeklyReminder(identifier: String, content: UNMutableNotificationContent, hour: Int, minute: Int, weekday: Int) async {
        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(identifier)_weekly",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("[NotificationService] Failed to schedule weekly: \(error.localizedDescription)")
        }
    }

    /// Schedule reminders throughout the day at the given interval
    private func scheduleDaytimeReminders(
        identifier: String,
        content: UNMutableNotificationContent,
        intervalMinutes: Int,
        quietHoursStart: Int,
        quietHoursEnd: Int
    ) async {
        // Schedule repeating notifications during active hours
        for hour in quietHoursEnd..<quietHoursEnd+24 {
            let actualHour = hour % 24
            if actualHour >= quietHoursStart || actualHour < quietHoursEnd {
                continue // Skip quiet hours
            }

            // Schedule notifications at this hour based on interval
            let minuteIntervals = stride(from: 0, to: 60, by: max(intervalMinutes, 15))
            for minute in minuteIntervals {
                var dateComponents = DateComponents()
                dateComponents.hour = actualHour
                dateComponents.minute = minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(identifier)_\(actualHour)_\(minute)",
                    content: content,
                    trigger: trigger
                )

                do {
                    try await notificationCenter.add(request)
                } catch {
                    print("[NotificationService] Failed to schedule: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelReminder(for interventionId: String) async {
        let prefix = "intervention_\(interventionId)"
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let matchingIds = pendingRequests
            .filter { $0.identifier.hasPrefix(prefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: matchingIds)
        print("[NotificationService] Cancelled \(matchingIds.count) reminders for \(interventionId)")
    }

    // MARK: - Grouped Reminders

    /// Schedule a combined reminder for a group of interventions
    func scheduleGroupReminder(
        group: ReminderGroup,
        definitions: [InterventionDefinition],
        quietHoursStart: Int = 22,
        quietHoursEnd: Int = 8
    ) async {
        if !isAuthorized {
            await requestAuthorization()
            if !isAuthorized { return }
        }

        // Cancel existing reminders for all group members
        for id in group.interventionIds {
            await cancelReminder(for: id)
        }
        await cancelGroupReminder(groupId: group.id)

        let identifier = "group_\(group.id.uuidString)"

        // Create combined notification content
        let content = UNMutableNotificationContent()
        content.title = group.name
        content.body = groupReminderMessage(for: definitions)
        content.sound = .default
        content.categoryIdentifier = "INTERVENTION_REMINDER"
        content.userInfo = ["groupId": group.id.uuidString]

        // Handle different interval types
        let intervalMinutes = group.intervalMinutes
        let hour = group.reminderHour
        let minute = group.reminderMinute
        let weekday = group.reminderWeekday

        if intervalMinutes == Self.weekdaysOnly {
            await scheduleWeekdayReminders(identifier: identifier, content: content, hour: hour, minute: minute)
            print("[NotificationService] Scheduled weekday group reminders for '\(group.name)'")
        } else if intervalMinutes >= 10080 {
            await scheduleWeeklyReminder(identifier: identifier, content: content, hour: hour, minute: minute, weekday: weekday)
            print("[NotificationService] Scheduled weekly group reminder for '\(group.name)'")
        } else if intervalMinutes >= 1440 {
            await scheduleDailyReminder(identifier: identifier, content: content, hour: hour, minute: minute)
            print("[NotificationService] Scheduled daily group reminder for '\(group.name)'")
        } else {
            await scheduleDaytimeReminders(
                identifier: identifier,
                content: content,
                intervalMinutes: intervalMinutes,
                quietHoursStart: quietHoursStart,
                quietHoursEnd: quietHoursEnd
            )
            print("[NotificationService] Scheduled group reminders for '\(group.name)' every \(intervalMinutes) min")
        }
    }

    /// Cancel all reminders for a group
    func cancelGroupReminder(groupId: UUID) async {
        let prefix = "group_\(groupId.uuidString)"
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let matchingIds = pendingRequests
            .filter { $0.identifier.hasPrefix(prefix) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: matchingIds)
        print("[NotificationService] Cancelled \(matchingIds.count) group reminders for \(groupId)")
    }

    /// Generate a combined message for grouped interventions
    private func groupReminderMessage(for definitions: [InterventionDefinition]) -> String {
        if definitions.isEmpty {
            return "Time to check in"
        }

        let names = definitions.map { "\($0.emoji) \($0.name)" }

        if names.count == 1 {
            return "Time for: \(names[0])"
        } else if names.count == 2 {
            return "Time for: \(names[0]) & \(names[1])"
        } else {
            // List all items
            let allNames = names.joined(separator: ", ")
            return "Time for: \(allNames)"
        }
    }

    func cancelAllReminders() {
        notificationCenter.removeAllPendingNotificationRequests()
        print("[NotificationService] Cancelled all reminders")
    }

    // MARK: - Helpers

    private func reminderMessage(for intervention: InterventionDefinition) -> String {
        switch intervention.id {
        case "tongue_posture":
            return "Check your tongue position - rest it on the roof of your mouth"
        case "jaw_relaxation":
            return "Let your jaw hang loose and relax"
        case "physical_therapy":
            return "Time for your jaw exercises"
        case "posture":
            return "Check your posture - head up, shoulders back"
        case "biofeedback":
            return "Charge your Muse headband for tonight"
        default:
            return "Time to practice \(intervention.name)"
        }
    }

    // MARK: - Notification Actions

    func setupNotificationCategories() {
        let doneAction = UNNotificationAction(
            identifier: "DONE_ACTION",
            title: "Done",
            options: []
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 15 min",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "INTERVENTION_REMINDER",
            actions: [doneAction, snoozeAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        notificationCenter.setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let notificationIdentifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        // Handle tap on notification body (not action button) - show quick check modal
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            await handleNotificationTap(identifier: notificationIdentifier, userInfo: userInfo)
            return
        }

        // Extract intervention ID from notification identifier (nonisolated helper)
        if let interventionId = Self.extractInterventionId(from: notificationIdentifier) {
            switch actionIdentifier {
            case "DONE_ACTION":
                print("[NotificationService] User marked \(interventionId) as done")
                // Post notification to be handled by the main app
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("interventionCompletedFromNotification"),
                        object: nil,
                        userInfo: ["interventionId": interventionId]
                    )
                }
            case "SNOOZE_ACTION":
                print("[NotificationService] User snoozed \(interventionId)")
                // Schedule a one-time reminder in 15 minutes
                await scheduleSnoozeNonisolated(interventionId: interventionId)
            default:
                break
            }
        }
    }

    /// Handle notification tap - post event to show quick check modal
    nonisolated private func handleNotificationTap(identifier: String, userInfo: [AnyHashable: Any]) async {
        var interventionIds: [String] = []

        // Check if this is a group notification
        if let groupId = userInfo["groupId"] as? String {
            // For group notifications, we need to look up the group members
            // This will be handled by ContentView which has access to InterventionService
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .notificationTapped,
                    object: nil,
                    userInfo: ["groupId": groupId]
                )
            }
            print("[NotificationService] User tapped group notification: \(groupId)")
            return
        }

        // Extract single intervention ID
        if let interventionId = Self.extractInterventionId(from: identifier) {
            interventionIds = [interventionId]
        }

        guard !interventionIds.isEmpty else { return }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .notificationTapped,
                object: nil,
                userInfo: ["interventionIds": interventionIds]
            )
        }
        print("[NotificationService] User tapped notification for: \(interventionIds)")
    }

    // Nonisolated helper for extracting intervention ID
    nonisolated private static func extractInterventionId(from identifier: String) -> String? {
        // Format: intervention_<id>_<hour>_<minute>
        let parts = identifier.split(separator: "_")
        if parts.count >= 2 {
            return String(parts[1])
        }
        return nil
    }

    // Nonisolated snooze scheduling - uses MainActor.run to access catalog
    nonisolated private func scheduleSnoozeNonisolated(interventionId: String) async {
        // Get definition on main actor using CatalogDataService
        let definitionInfo: (name: String, message: String)? = await MainActor.run {
            let catalogService = CatalogDataService()
            guard let definition = catalogService.find(byId: interventionId) else { return nil }
            return (name: definition.name, message: Self.reminderMessageStatic(for: interventionId))
        }

        guard let info = definitionInfo else { return }

        let content = UNMutableNotificationContent()
        content.title = info.name
        content.body = info.message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "snooze_\(interventionId)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[NotificationService] Scheduled snooze for \(interventionId)")
        } catch {
            print("[NotificationService] Failed to schedule snooze: \(error.localizedDescription)")
        }
    }

    // Static helper for reminder messages (nonisolated, uses id string)
    nonisolated private static func reminderMessageStatic(for interventionId: String) -> String {
        switch interventionId {
        case "tongue_posture":
            return "Check your tongue position - rest it on the roof of your mouth"
        case "jaw_relaxation":
            return "Let your jaw hang loose and relax"
        case "physical_therapy":
            return "Time for your jaw exercises"
        case "posture":
            return "Check your posture - head up, shoulders back"
        case "biofeedback":
            return "Charge your Muse headband for tonight"
        default:
            return "Time to practice your habit"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let interventionCompletedFromNotification = Notification.Name("interventionCompletedFromNotification")
    static let notificationTapped = Notification.Name("notificationTapped")
}
