//
//  InterventionDetailView.swift
//  Skywalker
//
//  OpenJaw - Configure and view history for a single intervention
//

import SwiftUI

struct InterventionDetailView: View {
    let definition: InterventionDefinition
    var interventionService: InterventionService

    @Environment(\.dismiss) var dismiss
    @Environment(\.catalogDataService) var catalogDataService
    @State private var reminderEnabled = false
    @State private var reminderInterval = 15
    @State private var reminderTime = Date()
    @State private var reminderWeekday = 1  // 1 = Sunday
    @State private var notificationService = NotificationService()
    @State private var showGroupSelection = false

    private var userIntervention: UserIntervention? {
        interventionService.userInterventions.first { $0.interventionId == definition.id }
    }

    private var recentCompletions: [InterventionCompletion] {
        interventionService.completions(for: definition.id, inLast: 7)
    }

    var body: some View {
        NavigationView {
            List {
                // Info section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(definition.emoji)
                                .font(.system(size: 48))

                            VStack(alignment: .leading) {
                                Text(definition.name)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                HStack {
                                    tierBadge
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(definition.frequency.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Text(definition.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let link = definition.externalLink {
                            Link(destination: link) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("Learn more")
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Evidence section (new)
                if definition.evidenceLevel != nil || definition.evidenceSummary != nil {
                    Section("Evidence") {
                        if let level = definition.evidenceLevel {
                            HStack {
                                Text("Evidence Level")
                                Spacer()
                                Text(level)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let summary = definition.evidenceSummary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Citations for this intervention
                        if !definition.citationIds.isEmpty {
                            let citations = catalogDataService.citations(forIds: definition.citationIds)
                            if !citations.isEmpty {
                                ForEach(citations) { citation in
                                    CitationRow(citation: citation)
                                }
                            }
                        }
                    }
                }

                // ROI and cost info (new)
                if definition.roiTier != nil || definition.costRange != nil || definition.easeScore != nil {
                    Section("Implementation") {
                        if let roi = definition.roiTier {
                            HStack {
                                Text("ROI Tier")
                                Spacer()
                                roiTierBadge(roi)
                            }
                        }

                        if let ease = definition.easeScore {
                            HStack {
                                Text("Ease of Implementation")
                                Spacer()
                                Text("\(ease)/10")
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let cost = definition.costRange {
                            HStack {
                                Text("Cost")
                                Spacer()
                                Text(cost)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Reminder settings (if remindable)
                if definition.isRemindable {
                    Section("Reminders") {
                        Toggle("Enable reminders", isOn: $reminderEnabled)
                            .onChange(of: reminderEnabled) { _, newValue in
                                updateReminders(enabled: newValue)
                            }

                        if reminderEnabled {
                            Picker("Remind every", selection: $reminderInterval) {
                                // Daytime awareness reminders (short intervals)
                                Text("15 minutes").tag(15)
                                Text("30 minutes").tag(30)
                                Text("1 hour").tag(60)
                                Text("2 hours").tag(120)
                                Text("3 hours").tag(180)
                                Text("4 hours").tag(240)

                                // Daily/Weekly reminders
                                Text("Once a day").tag(1440)
                                Text("Weekdays only").tag(-5)  // Special value for weekdays
                                Text("Once a week").tag(10080)
                            }
                            .onChange(of: reminderInterval) { _, _ in
                                updateReminders(enabled: true)
                            }

                            // Show time picker for daily/weekly/weekday reminders
                            if reminderInterval >= 1440 || reminderInterval == -5 {
                                DatePicker(
                                    "Time",
                                    selection: $reminderTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .onChange(of: reminderTime) { _, _ in
                                    updateReminders(enabled: true)
                                }

                                // Show weekday picker for weekly reminders only
                                if reminderInterval >= 10080 {
                                    Picker("Day", selection: $reminderWeekday) {
                                        Text("Sunday").tag(1)
                                        Text("Monday").tag(2)
                                        Text("Tuesday").tag(3)
                                        Text("Wednesday").tag(4)
                                        Text("Thursday").tag(5)
                                        Text("Friday").tag(6)
                                        Text("Saturday").tag(7)
                                    }
                                    .onChange(of: reminderWeekday) { _, _ in
                                        updateReminders(enabled: true)
                                    }
                                }
                            }

                            // Grouping section for short-interval reminders
                            if reminderInterval > 0 && reminderInterval < 1440 {
                                groupingSection
                            }
                        }
                    }
                }

                // Today's progress
                Section("Today") {
                    let todayCount = interventionService.todayCompletionCount(for: definition.id)

                    HStack {
                        Text("Completions")
                        Spacer()

                        // Stepper-style controls
                        HStack(spacing: 16) {
                            // Minus button
                            Button(action: undoLastCompletion) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(todayCount > 0 ? .red : .secondary.opacity(0.3))
                            }
                            .disabled(todayCount == 0)
                            .buttonStyle(BorderlessButtonStyle())

                            // Count
                            Text("\(todayCount)")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(todayCount > 0 ? .green : .secondary)
                                .frame(minWidth: 30)

                            // Plus button
                            Button(action: logCompletion) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }

                // Recent history
                if !recentCompletions.isEmpty {
                    Section("Last 7 Days") {
                        ForEach(groupedByDay(), id: \.date) { day in
                            HStack {
                                Text(day.date, style: .date)
                                Spacer()
                                Text("\(day.count)")
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Actions
                Section {
                    Button(action: removeIntervention) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remove from habits")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
            .sheet(isPresented: $showGroupSelection) {
                ReminderGroupSelectionView(
                    currentInterventionId: definition.id,
                    interventionService: interventionService,
                    onSelectionChanged: {
                        updateReminders(enabled: reminderEnabled)
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var groupingSection: some View {
        let group = interventionService.getGroup(for: definition.id)

        if let group = group {
            // Show grouped interventions
            DisclosureGroup {
                ForEach(group.interventionIds, id: \.self) { memberId in
                    if memberId != definition.id,
                       let memberDef = catalogDataService.find(byId: memberId) {
                        HStack {
                            Text(memberDef.emoji)
                            Text(memberDef.name)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                interventionService.removeFromGroup(memberId)
                                updateReminders(enabled: true)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    showGroupSelection = true
                } label: {
                    Label("Add more", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            } label: {
                HStack {
                    Text("Combined with")
                    Spacer()
                    Text("\(group.interventionIds.count - 1) other\(group.interventionIds.count == 2 ? "" : "s")")
                        .foregroundColor(.secondary)
                }
            }
        } else {
            // Not grouped yet
            Button {
                showGroupSelection = true
            } label: {
                HStack {
                    Text("Combine with other reminders")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
        }
    }

    private var tierBadge: some View {
        Text(definition.tier.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tierColor.opacity(0.2))
            .foregroundColor(tierColor)
            .cornerRadius(4)
    }

    @ViewBuilder
    private func roiTierBadge(_ tier: String) -> some View {
        let color: Color = {
            switch tier {
            case "A": return .green
            case "B": return .blue
            case "C": return .orange
            case "D": return .red
            case "E": return .gray
            default: return .gray
            }
        }()

        Text("Tier \(tier)")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    // MARK: - Helpers

    private var tierColor: Color {
        switch definition.tier {
        case .strong: return .blue
        case .moderate: return .orange
        case .lower: return .purple
        }
    }

    private func loadSettings() {
        if let intervention = userIntervention {
            reminderEnabled = intervention.reminderEnabled
            reminderInterval = intervention.reminderIntervalMinutes

            // Load time settings
            let hour = intervention.reminderHour ?? 18
            let minute = intervention.reminderMinute ?? 0
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = Calendar.current.date(from: components) {
                reminderTime = date
            }

            reminderWeekday = intervention.reminderWeekday ?? 1
        } else if let defaultMinutes = definition.defaultReminderMinutes {
            reminderInterval = defaultMinutes

            // Default time: 6 PM
            var components = DateComponents()
            components.hour = 18
            components.minute = 0
            if let date = Calendar.current.date(from: components) {
                reminderTime = date
            }
        }
    }

    private func updateReminders(enabled: Bool) {
        guard var intervention = userIntervention else { return }

        intervention.reminderEnabled = enabled
        intervention.reminderIntervalMinutes = reminderInterval

        // Save time settings
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        intervention.reminderHour = components.hour
        intervention.reminderMinute = components.minute
        intervention.reminderWeekday = reminderWeekday

        interventionService.updateIntervention(intervention)

        Task {
            if enabled {
                // Check if this intervention is part of a group
                if let group = interventionService.getGroup(for: definition.id) {
                    await notificationService.scheduleGroupReminder(
                        group: group,
                        definitions: interventionService.definitions(for: group)
                    )
                } else {
                    await notificationService.scheduleReminder(
                        for: definition,
                        intervalMinutes: reminderInterval,
                        hour: components.hour ?? 18,
                        minute: components.minute ?? 0,
                        weekday: reminderWeekday
                    )
                }
            } else {
                await notificationService.cancelReminder(for: definition.id)
            }
        }
    }

    private func logCompletion() {
        switch definition.trackingType {
        case .binary:
            interventionService.logCompletion(interventionId: definition.id, value: .binary(true))
        case .counter:
            interventionService.logCompletion(interventionId: definition.id, value: .count(1))
        default:
            break
        }
    }

    private func undoLastCompletion() {
        interventionService.removeLastCompletion(for: definition.id)
    }

    private func removeIntervention() {
        interventionService.removeIntervention(definition.id)
        Task {
            await notificationService.cancelReminder(for: definition.id)
        }
        dismiss()
    }

    private func groupedByDay() -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        var grouped: [Date: Int] = [:]

        for completion in recentCompletions {
            let day = calendar.startOfDay(for: completion.timestamp)
            grouped[day, default: 0] += 1
        }

        return grouped.map { (date: $0.key, count: $0.value) }
            .sorted { $0.date > $1.date }
    }
}

#Preview {
    InterventionDetailView(
        definition: InterventionDefinition(
            id: "tongue_posture",
            name: "Tongue Posture",
            emoji: "👅",
            icon: "mouth.fill",
            description: "Keep tongue resting on the roof of mouth with teeth slightly apart.",
            tier: .moderate,
            frequency: .hourly,
            trackingType: .counter,
            isRemindable: true,
            defaultReminderMinutes: 15,
            evidenceLevel: "Low-Moderate",
            evidenceSummary: "Clinical experience supports jaw positioning. Most effective for awake bruxism.",
            roiTier: "A",
            easeScore: 10,
            costRange: "$0"
        ),
        interventionService: InterventionService()
    )
}
