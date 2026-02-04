//
//  InterventionsSectionView.swift
//  Skywalker
//
//  OpenJaw - Home screen interventions section with habit cards organized by time of day
//

import SwiftUI
import UniformTypeIdentifiers

struct InterventionsSectionView: View {
    var interventionService: InterventionService
    var routineService: RoutineService
    var onShowUndoToast: ((InterventionDefinition) -> Void)?
    @State private var showingCatalog = false
    @State private var selectedIntervention: InterventionDefinition?
    @State private var expandedSections: Set<TimeOfDaySection> = InterventionsSectionView.defaultExpandedSections()
    @State private var sectionOrders: [TimeOfDaySection: [String]] = [:]
    @State private var draggingInterventionId: String?
    @State private var showingResetScoresConfirmation = false
    @State private var showingResetPlanConfirmation = false

    // MARK: - Computed Properties

    private func habitsByCategory(_ category: TimeOfDaySection) -> [(UserIntervention, InterventionDefinition)] {
        interventionService.enabledInterventions().compactMap { userIntervention in
            guard let definition = interventionService.interventionDefinition(for: userIntervention),
                  definition.timeOfDaySections.contains(category) else {
                return nil
            }
            return (userIntervention, definition)
        }
    }

    private func orderedHabits(for category: TimeOfDaySection) -> [(UserIntervention, InterventionDefinition)] {
        let habits = habitsByCategory(category)
        let orderIds = sectionOrders[category] ?? []
        let orderIndex = Dictionary(uniqueKeysWithValues: orderIds.enumerated().map { ($1, $0) })

        return habits.sorted { lhs, rhs in
            // 1. Primary: Evidence tier (1 = strongest evidence, shown first)
            if lhs.1.tier.rawValue != rhs.1.tier.rawValue {
                return lhs.1.tier.rawValue < rhs.1.tier.rawValue
            }

            // 2. Secondary: User's custom drag-drop order
            let lhsIndex = orderIndex[lhs.1.id] ?? Int.max
            let rhsIndex = orderIndex[rhs.1.id] ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }

            // 3. Tertiary: defaultOrder from JSON
            let lhsDefault = lhs.1.defaultOrder ?? Int.max
            let rhsDefault = rhs.1.defaultOrder ?? Int.max
            if lhsDefault != rhsDefault {
                return lhsDefault < rhsDefault
            }

            // 4. Quaternary: Alphabetical
            return lhs.1.name.localizedCaseInsensitiveCompare(rhs.1.name) == .orderedAscending
        }
    }

    // MARK: - Sub-Block Helpers

    /// Get habits for a specific sub-block
    private func habitsForSubBlock(_ subBlock: SubBlock, in section: TimeOfDaySection) -> [(UserIntervention, InterventionDefinition)] {
        let allHabits = orderedHabits(for: section)

        // For the final pre-bed block, include end-of-day reflection items from anytime
        if subBlock == .preBedLightsOut {
            let preBedHabits = allHabits.filter { $0.1.assignedSubBlock(for: section) == subBlock }
            let reflectionHabits = orderedHabits(for: .anytime).filter { $0.1.isEndOfDayReflection }
            return preBedHabits + reflectionHabits
        }

        return allHabits.filter { $0.1.assignedSubBlock(for: section) == subBlock }
    }

    /// Calculate progress for a sub-block
    private func subBlockProgress(_ subBlock: SubBlock, in section: TimeOfDaySection) -> (completed: Int, total: Int) {
        let habits = habitsForSubBlock(subBlock, in: section)
        let completed = habits.filter { interventionService.isCompletedToday($0.1.id) }.count
        return (completed, habits.count)
    }

    /// Determine visibility state for a sub-block
    private func subBlockVisibility(_ subBlock: SubBlock, in section: TimeOfDaySection) -> BlockVisibility {
        let subBlocks = SubBlock.subBlocks(for: section)
        guard let targetIndex = subBlocks.firstIndex(of: subBlock) else {
            return .hidden
        }

        // Check if this block is complete
        let progress = subBlockProgress(subBlock, in: section)
        let isComplete = progress.total > 0 && progress.completed >= progress.total

        if isComplete {
            return .completed
        }

        // Check if all previous blocks are complete
        let previousBlocks = subBlocks.prefix(targetIndex)
        let allPreviousComplete = previousBlocks.allSatisfy { block in
            let p = subBlockProgress(block, in: section)
            return p.total == 0 || p.completed >= p.total
        }

        if allPreviousComplete {
            return .active
        }

        return .hidden
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

    private func hasAnyHabits(for category: TimeOfDaySection) -> Bool {
        !habitsByCategory(category).isEmpty
    }

    private var enabledInterventionIds: [String] {
        interventionService.enabledInterventions()
            .map { $0.interventionId }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            sectionHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // Time-of-day sections in display order
            VStack(spacing: 12) {
                ForEach(TimeOfDaySection.displayOrder, id: \.self) { category in
                    if hasAnyHabits(for: category) {
                        categorySection(for: category)
                    }
                }

                // Empty state if no habits at all
                if interventionService.enabledInterventions().isEmpty {
                    emptyState
                }

                // Reset Plan button (only show if there are habits)
                if !interventionService.enabledInterventions().isEmpty {
                    resetPlanButton
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
        .onAppear {
            loadSectionOrders()
            syncSectionOrders()
            expandedSections.insert(.anytime)
        }
        .onChange(of: enabledInterventionIds) { _ in
            syncSectionOrders()
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .foregroundColor(.green)
            Text("Daily Plan")
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

    private func categorySection(for category: TimeOfDaySection) -> some View {
        let ordered = orderedHabits(for: category)
        let completed = completedHabits(for: ordered)
        let totalCount = ordered.count
        let doneCount = completed.count
        let isExpanded = expandedSections.contains(category) || category == .anytime
        let subBlocks = SubBlock.subBlocks(for: category)
        let anchor = routineService.anchor(for: category)  // Get routine anchor if started

        return VStack(alignment: .leading, spacing: 8) {
            // Section header - tap to collapse/expand
            Button(action: { toggleSection(category) }) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(category.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        // Show relative time info if routine started, else default time window
                        if let anchor = anchor {
                            Text("Started at \(formatTime(anchor))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text(category.timeWindow)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("\(doneCount)/\(totalCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if category != .anytime {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, isExpanded ? 6 : 10)
                .padding(.horizontal, 10)
                .background(category.color.opacity(0.08))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            // Content (when expanded)
            if isExpanded {
                // For morning/pre-bed with active routine: show sub-blocks
                // For afternoon/evening or sections without anchor: show flat list
                if (category == .morning || category == .preBed) && anchor != nil && !subBlocks.isEmpty {
                    subBlocksView(for: category, subBlocks: subBlocks, anchor: anchor!)
                } else {
                    flatHabitList(for: category)
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }

    /// Flat list view for anytime section (no sub-blocks)
    @ViewBuilder
    private func flatHabitList(for category: TimeOfDaySection) -> some View {
        let ordered = orderedHabits(for: category)
        // Filter out end-of-day reflections from anytime (they appear in pre-bed)
        let filtered = category == .anytime
            ? ordered.filter { !$0.1.isEndOfDayReflection }
            : ordered
        let pending = pendingHabits(for: filtered)
        let completed = completedHabits(for: filtered)
        let orderBinding = bindingForSectionOrder(category)

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
            .onDrag {
                draggingInterventionId = definition.id
                return NSItemProvider(object: definition.id as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: ReorderDropDelegate(
                    itemId: definition.id,
                    order: orderBinding,
                    draggingId: $draggingInterventionId
                )
            )
        }

        // Inline completed subsection
        if !completed.isEmpty {
            inlineDoneSection(completed: completed)
        }
    }

    /// Sub-blocks view with sequential progression and relative time windows
    @ViewBuilder
    private func subBlocksView(for category: TimeOfDaySection, subBlocks: [SubBlock], anchor: Date) -> some View {
        ForEach(subBlocks, id: \.self) { subBlock in
            let visibility = subBlockVisibility(subBlock, in: category)
            let habits = habitsForSubBlock(subBlock, in: category)

            // Only show blocks that have habits or are relevant
            if !habits.isEmpty || visibility == .active {
                SubBlockView(
                    subBlock: subBlock,
                    anchor: anchor,  // Pass anchor for relative time display
                    habits: habits,
                    visibility: visibility,
                    interventionService: interventionService,
                    onTap: { definition, userIntervention in
                        handleTap(definition: definition, userIntervention: userIntervention)
                    },
                    onLongPress: { definition in
                        selectedIntervention = definition
                    }
                )
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

    private func toggleSection(_ category: TimeOfDaySection) {
        withAnimation {
            guard category != .anytime else {
                expandedSections.insert(.anytime)
                return
            }

            if expandedSections.contains(category) {
                expandedSections.remove(category)
            } else {
                expandedSections.insert(category)
            }

            expandedSections.insert(.anytime)
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

    // MARK: - Reset Buttons

    private var resetPlanButton: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 12)

            HStack(spacing: 24) {
                // Reset Scores button
                Button(action: { showingResetScoresConfirmation = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                        Text("Reset Scores")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())

                // Reset Plan button
                Button(action: { showingResetPlanConfirmation = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text("Reset Plan")
                            .font(.caption)
                    }
                    .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 14)
        }
        .alert("Reset Scores?", isPresented: $showingResetScoresConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Scores", role: .destructive) {
                interventionService.resetScores()
            }
        } message: {
            Text("This will clear all completion history and streaks. Your habits will remain.")
        }
        .alert("Reset Plan?", isPresented: $showingResetPlanConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Plan", role: .destructive) {
                interventionService.resetPlan()
            }
        } message: {
            Text("This will remove all habits and completion history. You'll need to add habits again.")
        }
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

    private static func defaultExpandedSections() -> Set<TimeOfDaySection> {
        if let current = TimeOfDaySection.currentSection() {
            return [current, .anytime]
        }
        return [.anytime]
    }

    private func orderStorageKey(for section: TimeOfDaySection) -> String {
        "interventionOrder.\(section.rawValue)"
    }

    private func loadSectionOrders() {
        var loaded: [TimeOfDaySection: [String]] = [:]
        let decoder = JSONDecoder()

        for section in TimeOfDaySection.allCases {
            let key = orderStorageKey(for: section)
            guard let data = UserDefaults.standard.data(forKey: key),
                  let ids = try? decoder.decode([String].self, from: data) else {
                continue
            }
            loaded[section] = ids
        }

        sectionOrders = loaded
    }

    private func saveSectionOrder(_ order: [String], for section: TimeOfDaySection) {
        let encoder = JSONEncoder()
        let key = orderStorageKey(for: section)
        guard let data = try? encoder.encode(order) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func bindingForSectionOrder(_ section: TimeOfDaySection) -> Binding<[String]> {
        Binding(
            get: { sectionOrders[section] ?? [] },
            set: { newValue in
                sectionOrders[section] = newValue
                saveSectionOrder(newValue, for: section)
            }
        )
    }

    private func syncSectionOrders() {
        var updated = sectionOrders

        for section in TimeOfDaySection.allCases {
            let habits = habitsByCategory(section)
            let habitIds = habits.map { $0.1.id }
            let existing = updated[section] ?? []

            var newOrder = existing.filter { habitIds.contains($0) }
            let missing = habitIds.filter { !newOrder.contains($0) }

            let missingSorted = missing.sorted { lhsId, rhsId in
                let lhsDef = habits.first { $0.1.id == lhsId }?.1
                let rhsDef = habits.first { $0.1.id == rhsId }?.1
                let lhsOrder = lhsDef?.defaultOrder ?? Int.max
                let rhsOrder = rhsDef?.defaultOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return (lhsDef?.name ?? lhsId).localizedCaseInsensitiveCompare(rhsDef?.name ?? rhsId) == .orderedAscending
            }

            newOrder.append(contentsOf: missingSorted)

            if newOrder != existing {
                updated[section] = newOrder
                saveSectionOrder(newOrder, for: section)
            }
        }

        updated[.anytime] = updated[.anytime] ?? []
        sectionOrders = updated
        expandedSections.insert(.anytime)
    }
}

// MARK: - Sub-Block View

private struct SubBlockView: View {
    let subBlock: SubBlock
    let anchor: Date  // Anchor time for relative calculation
    let habits: [(UserIntervention, InterventionDefinition)]
    let visibility: BlockVisibility
    var interventionService: InterventionService
    let onTap: (InterventionDefinition, UserIntervention) -> Void
    let onLongPress: (InterventionDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sub-block header
            subBlockHeader

            // Content based on visibility
            switch visibility {
            case .active:
                activeContent
            case .completed:
                completedSummary
            case .hidden:
                lockedContent
            }
        }
    }

    private var subBlockHeader: some View {
        let progress = completionProgress

        return HStack(spacing: 8) {
            Text(subBlock.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(visibility == .active ? .primary : .secondary)

            // Display calculated time window based on anchor
            Text(subBlock.timeWindowDisplay(anchoredAt: anchor))
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            // Progress or lock indicator
            switch visibility {
            case .active:
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Done")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            case .hidden:
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(visibility == .active ? Color.blue.opacity(0.06) : Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var activeContent: some View {
        let pending = habits.filter { !interventionService.isCompletedToday($0.1.id) }
        let completed = habits.filter { interventionService.isCompletedToday($0.1.id) }

        // Pending habits
        ForEach(pending, id: \.0.id) { userIntervention, definition in
            InterventionCardView(
                definition: definition,
                todayCount: interventionService.todayCompletionCount(for: userIntervention.interventionId),
                isCompletedToday: interventionService.isCompletedToday(userIntervention.interventionId),
                streak: interventionService.currentStreak(for: definition.id),
                onTap: { onTap(definition, userIntervention) },
                onLongPress: { onLongPress(definition) }
            )
        }

        // Completed items (compact)
        if !completed.isEmpty {
            ForEach(completed, id: \.0.id) { userIntervention, definition in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(definition.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .strikethrough()
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
                .onTapGesture {
                    interventionService.removeLastCompletion(for: definition.id)
                }
            }
        }
    }

    private var completedSummary: some View {
        HStack(spacing: 8) {
            ForEach(habits.prefix(3), id: \.0.id) { _, definition in
                Text(definition.emoji)
                    .font(.caption)
            }
            if habits.count > 3 {
                Text("+\(habits.count - 3)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.05))
        .cornerRadius(6)
    }

    private var lockedContent: some View {
        HStack {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Complete previous block to unlock")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private var completionProgress: (completed: Int, total: Int) {
        let completed = habits.filter { interventionService.isCompletedToday($0.1.id) }.count
        return (completed, habits.count)
    }
}

// MARK: - Reorder Drop Delegate

private struct ReorderDropDelegate: DropDelegate {
    let itemId: String
    @Binding var order: [String]
    @Binding var draggingId: String?

    func dropEntered(info: DropInfo) {
        guard let draggingId,
              draggingId != itemId,
              let fromIndex = order.firstIndex(of: draggingId),
              let toIndex = order.firstIndex(of: itemId) else {
            return
        }

        var updated = order
        updated.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        order = updated
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#Preview {
    InterventionsSectionView(
        interventionService: InterventionService(),
        routineService: RoutineService(),
        onShowUndoToast: { _ in }
    )
    .padding()
}
