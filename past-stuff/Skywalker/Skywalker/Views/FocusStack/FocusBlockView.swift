//
//  FocusBlockView.swift
//  Skywalker
//
//  OpenJaw - Individual focus block (expanded or collapsed)
//

import SwiftUI

struct FocusBlockView: View {
    let block: FocusBlock
    let isExpanded: Bool
    var interventionService: InterventionService
    var onToggleExpand: () -> Void
    var onShowUndoToast: ((InterventionDefinition) -> Void)?

    @State private var selectedDefinition: InterventionDefinition?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            FocusBlockHeaderView(
                block: block,
                isExpanded: isExpanded,
                onToggle: onToggleExpand
            )

            // Content (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()

                    // Item list
                    ForEach(Array(block.items.enumerated()), id: \.1.1.id) { index, item in
                        let (_, definition) = item
                        let isCompleted = interventionService.isCompletedToday(definition.id)

                        FocusItemRow(
                            definition: definition,
                            isCompleted: isCompleted,
                            onToggle: {
                                toggleCompletion(definition, isCompleted: isCompleted)
                            },
                            onLongPress: {
                                selectedDefinition = definition
                            }
                        )

                        if index < block.items.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .sheet(item: $selectedDefinition) { definition in
            FocusInterventionDetailSheet(definition: definition)
        }
    }

    private func toggleCompletion(_ definition: InterventionDefinition, isCompleted: Bool) {
        if isCompleted {
            interventionService.removeLastCompletion(for: definition.id)
        } else {
            // Log completion based on intervention type
            switch definition.trackingType {
            case .binary:
                interventionService.logCompletion(interventionId: definition.id, value: .binary(true))
            case .counter:
                interventionService.logCompletion(interventionId: definition.id, value: .count(1))
            case .timer:
                interventionService.logCompletion(interventionId: definition.id, value: .duration(0))
            case .checklist, .appointment, .automatic:
                interventionService.logCompletion(interventionId: definition.id, value: .binary(true))
            }
            onShowUndoToast?(definition)
        }
    }
}

// MARK: - Focus Item Row

struct FocusItemRow: View {
    let definition: InterventionDefinition
    let isCompleted: Bool
    var onToggle: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isCompleted ? .green : .secondary.opacity(0.5))
                    .frame(width: 28)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(definition.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(isCompleted ? .secondary : .primary)
                            .strikethrough(isCompleted)

                        // Evidence tier dots
                        tierDots
                    }

                    HStack(spacing: 8) {
                        // Duration
                        Text("\(definition.durationMinutes) min")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Energy indicator
                        Text(energyIndicator)
                            .font(.caption)
                    }
                }

                Spacer()

                // Completed indicator
                if isCompleted {
                    Text("Nice!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture { onLongPress() }
    }

    // MARK: - Evidence Tier Dots

    private var tierDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < filledDots ? tierColor : Color.gray.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var filledDots: Int {
        switch definition.tier {
        case .strong: return 3
        case .moderate: return 2
        case .lower: return 1
        }
    }

    private var tierColor: Color {
        switch definition.tier {
        case .strong: return .green
        case .moderate: return .blue
        case .lower: return .orange
        }
    }

    private var energyIndicator: String {
        switch definition.requiredEnergy {
        case .low: return "🌙"
        case .medium: return "☀️"
        case .high: return "⚡️"
        }
    }
}

// MARK: - Focus Intervention Detail Sheet

struct FocusInterventionDetailSheet: View {
    let definition: InterventionDefinition

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with name and tier
                    VStack(alignment: .leading, spacing: 8) {
                        Text(definition.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 8) {
                            tierBadge
                            energyBadge
                            durationBadge
                        }
                    }

                    Divider()

                    // Description
                    if !definition.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)

                            Text(definition.description)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Evidence section
                    if let evidenceSummary = definition.evidenceSummary, !evidenceSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Evidence")
                                .font(.headline)

                            Text(evidenceSummary)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Detailed description
                    if let detailedDescription = definition.detailedDescription, !detailedDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(.headline)

                            Text(detailedDescription)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var tierBadge: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < filledDots ? tierColor : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text(definition.tier.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tierColor.opacity(0.15))
        .foregroundColor(tierColor)
        .cornerRadius(6)
    }

    private var energyBadge: some View {
        HStack(spacing: 4) {
            Text(energyEmoji)
            Text(energyText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(energyColor.opacity(0.15))
        .foregroundColor(energyColor)
        .cornerRadius(6)
    }

    private var durationBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption)
            Text("\(definition.durationMinutes) min")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15))
        .foregroundColor(.blue)
        .cornerRadius(6)
    }

    private var filledDots: Int {
        switch definition.tier {
        case .strong: return 3
        case .moderate: return 2
        case .lower: return 1
        }
    }

    private var tierColor: Color {
        switch definition.tier {
        case .strong: return .green
        case .moderate: return .blue
        case .lower: return .orange
        }
    }

    private var energyEmoji: String {
        switch definition.requiredEnergy {
        case .low: return "🌙"
        case .medium: return "☀️"
        case .high: return "⚡️"
        }
    }

    private var energyText: String {
        switch definition.requiredEnergy {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    private var energyColor: Color {
        switch definition.requiredEnergy {
        case .low: return .purple
        case .medium: return .orange
        case .high: return .red
        }
    }
}

#Preview {
    VStack {
        // Create a mock block for preview
        Text("Preview requires InterventionService setup")
            .foregroundColor(.secondary)
    }
    .padding()
}
