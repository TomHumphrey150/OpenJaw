//
//  ReminderGroupSelectionView.swift
//  Skywalker
//
//  OpenJaw - Select interventions to group into combined reminders
//

import SwiftUI

struct ReminderGroupSelectionView: View {
    let currentInterventionId: String
    var interventionService: InterventionService
    var onSelectionChanged: () -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.catalogDataService) var catalogDataService
    @State private var selectedIds: Set<String> = []

    private var availableInterventions: [(UserIntervention, InterventionDefinition)] {
        interventionService.userInterventions
            .filter { userInt in
                // Include interventions that:
                // 1. Are not the current one
                // 2. Have reminders enabled
                // 3. Have a short interval (daytime reminders)
                userInt.interventionId != currentInterventionId &&
                userInt.reminderEnabled &&
                userInt.reminderIntervalMinutes > 0 &&
                userInt.reminderIntervalMinutes < 1440
            }
            .compactMap { userInt in
                guard let def = catalogDataService.find(byId: userInt.interventionId) else {
                    return nil
                }
                return (userInt, def)
            }
    }

    var body: some View {
        NavigationView {
            List {
                if availableInterventions.isEmpty {
                    Section {
                        Text("No other reminders available to combine with.\n\nAdd other habits with daytime reminders (15 min - 4 hours) to combine them.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        Text("Select habits to remind you about at the same time. All selected habits will share the same reminder interval.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }

                    Section("Available Reminders") {
                        ForEach(availableInterventions, id: \.1.id) { userInt, definition in
                            Button {
                                toggleSelection(definition.id)
                            } label: {
                                HStack {
                                    Text(definition.emoji)
                                        .font(.title2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(definition.name)
                                            .foregroundColor(.primary)

                                        Text("Every \(formatInterval(userInt.reminderIntervalMinutes))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if selectedIds.contains(definition.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !selectedIds.isEmpty {
                        Section {
                            let currentDef = catalogDataService.find(byId: currentInterventionId)
                            let shortestInterval = computeShortestInterval()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Combined reminder will include:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                // Current intervention
                                if let def = currentDef {
                                    HStack {
                                        Text(def.emoji)
                                        Text(def.name)
                                            .font(.subheadline)
                                    }
                                }

                                // Selected interventions
                                ForEach(Array(selectedIds), id: \.self) { id in
                                    if let def = catalogDataService.find(byId: id) {
                                        HStack {
                                            Text(def.emoji)
                                            Text(def.name)
                                                .font(.subheadline)
                                        }
                                    }
                                }

                                Divider()

                                Text("Reminder interval: every \(formatInterval(shortestInterval))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Text("Preview")
                        }
                    }
                }
            }
            .navigationTitle("Combine Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveGrouping()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadExistingGroup()
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func loadExistingGroup() {
        if let group = interventionService.getGroup(for: currentInterventionId) {
            // Load existing group members (excluding current)
            selectedIds = Set(group.interventionIds.filter { $0 != currentInterventionId })
        }
    }

    private func computeShortestInterval() -> Int {
        var intervals: [Int] = []

        // Current intervention's interval
        if let currentInt = interventionService.userInterventions.first(where: {
            $0.interventionId == currentInterventionId
        }) {
            intervals.append(currentInt.reminderIntervalMinutes)
        }

        // Selected interventions' intervals
        for id in selectedIds {
            if let userInt = interventionService.userInterventions.first(where: {
                $0.interventionId == id
            }) {
                intervals.append(userInt.reminderIntervalMinutes)
            }
        }

        return intervals.min() ?? 60
    }

    private func saveGrouping() {
        // Remove from any existing group first
        interventionService.removeFromGroup(currentInterventionId)

        if selectedIds.isEmpty {
            // No grouping needed
            onSelectionChanged()
            return
        }

        // Create a new group with current + selected interventions
        let allIds = [currentInterventionId] + Array(selectedIds)
        let shortestInterval = computeShortestInterval()

        // Generate a name from the interventions
        let names = allIds.compactMap { catalogDataService.find(byId: $0)?.name }
        let groupName = names.count <= 2
            ? names.joined(separator: " + ")
            : "\(names.first ?? "Reminder") + \(names.count - 1) more"

        interventionService.createGroup(
            name: groupName,
            interventionIds: allIds,
            intervalMinutes: shortestInterval
        )

        onSelectionChanged()
    }

    private func formatInterval(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else if minutes == 60 {
            return "1 hour"
        } else {
            let hours = minutes / 60
            return "\(hours) hours"
        }
    }
}

#Preview {
    ReminderGroupSelectionView(
        currentInterventionId: "tongue_posture",
        interventionService: InterventionService(),
        onSelectionChanged: {}
    )
}
