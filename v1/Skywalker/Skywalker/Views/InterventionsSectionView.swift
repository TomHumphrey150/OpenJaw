//
//  InterventionsSectionView.swift
//  Skywalker
//
//  OpenJaw - Home screen interventions section with habit cards organized by category
//

import SwiftUI

struct InterventionsSectionView: View {
    var interventionService: InterventionService
    var onShowUndoToast: ((InterventionDefinition) -> Void)?
    @State private var showingCatalog = false
    @State private var selectedIntervention: InterventionDefinition?
    @State private var expandedSections: Set<HabitCategory> = [.reminders, .rules, .quickTasks]

    // MARK: - Computed Properties

    private func habitsByCategory(_ category: HabitCategory) -> [(UserIntervention, InterventionDefinition)] {
        interventionService.enabledInterventions().compactMap { userIntervention in
            guard let definition = interventionService.interventionDefinition(for: userIntervention),
                  definition.category == category else {
                return nil
            }
            return (userIntervention, definition)
        }
    }

    private func pendingHabits(for habits: [(UserIntervention, InterventionDefinition)]) -> [(UserIntervention, InterventionDefinition)] {
        habits.filter { !isCompletedBinary($0) }
    }

    private func completedHabits(for habits: [(UserIntervention, InterventionDefinition)]) -> [(UserIntervention, InterventionDefinition)] {
        habits.filter { isCompletedBinary($0) }
    }

    private func isCompletedBinary(_ habit: (UserIntervention, InterventionDefinition)) -> Bool {
        habit.1.trackingType == .binary && interventionService.isCompletedToday(habit.1.id)
    }

    private func pendingCount(for habits: [(UserIntervention, InterventionDefinition)]) -> Int {
        habits.filter { !isCompletedBinary($0) }.count
    }

    private func hasAnyHabits(for category: HabitCategory) -> Bool {
        !habitsByCategory(category).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            sectionHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // Three category sections in display order (Quick Tasks, Reminders, Rules)
            VStack(spacing: 12) {
                ForEach(HabitCategory.displayOrder, id: \.self) { category in
                    if hasAnyHabits(for: category) {
                        categorySection(for: category, habits: habitsByCategory(category))
                    }
                }

                // Empty state if no habits at all
                if interventionService.enabledInterventions().isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showingCatalog) {
            InterventionCatalogView(interventionService: interventionService)
        }
        .sheet(item: $selectedIntervention) { definition in
            InterventionDetailView(
                definition: definition,
                interventionService: interventionService
            )
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .foregroundColor(.green)
            Text("Daily Habits")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { showingCatalog = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Category Section

    private func categorySection(for category: HabitCategory, habits: [(UserIntervention, InterventionDefinition)]) -> some View {
        let pending = pendingHabits(for: habits)
        let completed = completedHabits(for: habits)

        return VStack(alignment: .leading, spacing: 8) {
            // Section header - tap to collapse/expand
            Button(action: { toggleSection(category) }) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(category.color)
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("(\(pending.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: expandedSections.contains(category) ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(category.color.opacity(0.08))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            // Habit cards (when expanded)
            if expandedSections.contains(category) {
                // Pending habits
                ForEach(pending, id: \.0.id) { userIntervention, definition in
                    InterventionCardView(
                        definition: definition,
                        todayCount: interventionService.todayCompletionCount(for: userIntervention.interventionId),
                        isCompletedToday: interventionService.isCompletedToday(userIntervention.interventionId),
                        streak: interventionService.currentStreak(for: definition.id),
                        onTap: {
                            handleTap(definition: definition, userIntervention: userIntervention)
                        },
                        onLongPress: {
                            selectedIntervention = definition
                        }
                    )
                }

                // Inline completed subsection
                if !completed.isEmpty {
                    inlineDoneSection(completed: completed)
                }
            }
        }
    }

    /// Inline "Done" subsection within a category
    private func inlineDoneSection(completed: [(UserIntervention, InterventionDefinition)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // "Done" header
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                    .frame(width: 12)
                Text("Done")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.top, 4)

            // Completed habit rows (compact)
            ForEach(completed, id: \.0.id) { userIntervention, definition in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(definition.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Streak badge for completed items
                    let streak = interventionService.currentStreak(for: definition.id)
                    if streak > 1 {
                        HStack(spacing: 2) {
                            Text("\u{1F525}")
                                .font(.caption2)
                            Text("\(streak)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .opacity(0.8)
                .onTapGesture {
                    // Tap to uncomplete
                    interventionService.removeLastCompletion(for: definition.id)
                }
            }
        }
    }

    private func toggleSection(_ category: HabitCategory) {
        withAnimation {
            if expandedSections.contains(category) {
                expandedSections.remove(category)
            } else {
                expandedSections.insert(category)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Button(action: { showingCatalog = true }) {
            VStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green.opacity(0.6))
                Text("No habits added yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Tap to browse interventions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Actions

    private func handleTap(definition: InterventionDefinition, userIntervention: UserIntervention) {
        switch definition.trackingType {
        case .binary:
            // Toggle completion
            if !interventionService.isCompletedToday(definition.id) {
                interventionService.logCompletion(interventionId: definition.id, value: .binary(true))
                showCompletionToast(for: definition)
            }
        case .counter:
            // Increment counter
            interventionService.logCompletion(interventionId: definition.id, value: .count(1))
            showCompletionToast(for: definition)
        case .timer:
            // For now, just mark as done
            if !interventionService.isCompletedToday(definition.id) {
                interventionService.logCompletion(interventionId: definition.id, value: .duration(0))
                showCompletionToast(for: definition)
            }
        case .checklist:
            // Open detail view
            selectedIntervention = definition
        case .appointment, .automatic:
            // Open detail view
            selectedIntervention = definition
        }
    }

    private func showCompletionToast(for definition: InterventionDefinition) {
        onShowUndoToast?(definition)
    }
}

#Preview {
    InterventionsSectionView(
        interventionService: InterventionService(),
        onShowUndoToast: { _ in }
    )
    .padding()
}
