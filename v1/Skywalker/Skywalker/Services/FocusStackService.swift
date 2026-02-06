//
//  FocusStackService.swift
//  Skywalker
//
//  OpenJaw - Computes Now/Next/Later focus blocks based on time and capacity
//

import Foundation

/// Represents the state of a focus block (Now, Next, or Later)
enum FocusBlockState: Equatable {
    case now
    case next
    case later
    case completed
}

/// A focus block containing interventions for a time section
struct FocusBlock: Identifiable {
    let id = UUID()
    let section: TimeOfDaySection
    let state: FocusBlockState
    let items: [(UserIntervention, InterventionDefinition)]
    let completedCount: Int
    let totalCount: Int
    /// IDs of completed items (for calculating remaining duration)
    let completedIds: Set<String>

    /// Total estimated duration in minutes for remaining items
    var remainingDurationMinutes: Int {
        items.filter { !completedIds.contains($0.1.id) }.reduce(0) { $0 + $1.1.durationMinutes }
    }

    /// Total estimated duration for all items
    var totalDurationMinutes: Int {
        items.reduce(0) { $0 + $1.1.durationMinutes }
    }

    /// Whether this block is fully completed
    var isFullyCompleted: Bool {
        totalCount > 0 && completedCount >= totalCount
    }

    /// Progress percentage (0.0 to 1.0)
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

/// Service to compute and manage focus stack blocks
@Observable
class FocusStackService {

    // MARK: - Public Methods

    /// Compute focus blocks based on current time and capacity filter
    func computeFocusBlocks(
        interventionService: InterventionService,
        capacity: UserCapacity?
    ) -> [FocusBlock] {
        let currentSection = TimeOfDaySection.currentSection() ?? .morning

        var blocks: [FocusBlock] = []

        // Get all sections in display order
        for section in TimeOfDaySection.displayOrder {
            guard section != .anytime else { continue } // Handle anytime separately

            let items = getInterventions(
                for: section,
                interventionService: interventionService,
                capacity: capacity
            )

            guard !items.isEmpty else { continue }

            let completedIds = Set(items.filter { interventionService.isCompletedToday($0.1.id) }.map { $0.1.id })
            let completedCount = completedIds.count
            let state = determineBlockState(
                section: section,
                currentSection: currentSection,
                isFullyCompleted: completedCount >= items.count
            )

            blocks.append(FocusBlock(
                section: section,
                state: state,
                items: items,
                completedCount: completedCount,
                totalCount: items.count,
                completedIds: completedIds
            ))
        }

        return blocks
    }

    /// Get only the "Now" block (current section)
    func getCurrentBlock(
        interventionService: InterventionService,
        capacity: UserCapacity?
    ) -> FocusBlock? {
        let blocks = computeFocusBlocks(interventionService: interventionService, capacity: capacity)
        return blocks.first { $0.state == .now }
    }

    // MARK: - Private Methods

    private func getInterventions(
        for section: TimeOfDaySection,
        interventionService: InterventionService,
        capacity: UserCapacity?
    ) -> [(UserIntervention, InterventionDefinition)] {
        let allItems = interventionService.enabledInterventions().compactMap { userIntervention -> (UserIntervention, InterventionDefinition)? in
            guard let definition = interventionService.interventionDefinition(for: userIntervention),
                  definition.timeOfDaySections.contains(section) else {
                return nil
            }
            return (userIntervention, definition)
        }

        // Apply capacity filter if provided
        guard let capacity = capacity else {
            return sortedByPriority(allItems)
        }

        // Filter by time AND energy
        let filtered = allItems.filter { _, definition in
            definition.durationMinutes <= capacity.availableMinutes &&
            capacity.maxEnergy.numericValue >= definition.requiredEnergy.numericValue
        }

        return sortedByPriority(filtered)
    }

    private func sortedByPriority(_ items: [(UserIntervention, InterventionDefinition)]) -> [(UserIntervention, InterventionDefinition)] {
        items.sorted { lhs, rhs in
            // 1. Evidence tier (lower = stronger evidence)
            if lhs.1.tier.rawValue != rhs.1.tier.rawValue {
                return lhs.1.tier.rawValue < rhs.1.tier.rawValue
            }

            // 2. Default order from JSON
            let lhsOrder = lhs.1.defaultOrder ?? Int.max
            let rhsOrder = rhs.1.defaultOrder ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            // 3. Alphabetical
            return lhs.1.name.localizedCaseInsensitiveCompare(rhs.1.name) == .orderedAscending
        }
    }

    private func determineBlockState(
        section: TimeOfDaySection,
        currentSection: TimeOfDaySection,
        isFullyCompleted: Bool
    ) -> FocusBlockState {
        if isFullyCompleted {
            return .completed
        }

        let sectionOrder = sectionIndex(section)
        let currentOrder = sectionIndex(currentSection)

        if sectionOrder == currentOrder {
            return .now
        } else if sectionOrder == currentOrder + 1 {
            return .next
        } else {
            // Past sections and far future sections are "later"
            return .later
        }
    }

    private func sectionIndex(_ section: TimeOfDaySection) -> Int {
        switch section {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        case .preBed: return 3
        case .anytime: return 4
        }
    }
}
