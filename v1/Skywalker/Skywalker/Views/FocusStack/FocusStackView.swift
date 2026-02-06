//
//  FocusStackView.swift
//  Skywalker
//
//  OpenJaw - Main container for Now/Next/Later focus stack
//

import SwiftUI

struct FocusStackView: View {
    var interventionService: InterventionService
    var routineService: RoutineService
    var capacity: UserCapacity?
    var onShowUndoToast: ((InterventionDefinition) -> Void)?

    @State private var focusStackService = FocusStackService()
    @State private var expandedBlocks: Set<TimeOfDaySection> = []

    private var focusBlocks: [FocusBlock] {
        focusStackService.computeFocusBlocks(
            interventionService: interventionService,
            capacity: capacity
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(focusBlocks) { block in
                FocusBlockView(
                    block: block,
                    isExpanded: expandedBlocks.contains(block.section) || block.state == .now,
                    interventionService: interventionService,
                    onToggleExpand: { toggleExpand(block.section) },
                    onShowUndoToast: onShowUndoToast
                )
            }

            if focusBlocks.isEmpty {
                emptyStateView
            }
        }
    }

    private func toggleExpand(_ section: TimeOfDaySection) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expandedBlocks.contains(section) {
                expandedBlocks.remove(section)
            } else {
                expandedBlocks.insert(section)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("All done for today!")
                .font(.headline)
                .foregroundColor(.primary)

            Text("You've completed all your habits. Great work!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

#Preview {
    ScrollView {
        FocusStackView(
            interventionService: InterventionService(),
            routineService: RoutineService(),
            capacity: UserCapacity(availableMinutes: 15, maxEnergy: .medium),
            onShowUndoToast: nil
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
