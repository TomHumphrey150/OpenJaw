//
//  QuickCheckModal.swift
//  Skywalker
//
//  OpenJaw - Quick checklist modal for notification tap-through
//

import SwiftUI

struct QuickCheckModal: View {
    let interventionIds: [String]
    var interventionService: InterventionService
    @Environment(\.dismiss) private var dismiss
    @State private var completedIds: Set<String> = []
    @State private var showCelebration = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)

                    Text("Quick Check")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Tap to mark as done")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Checklist
                VStack(spacing: 12) {
                    ForEach(definitions, id: \.id) { definition in
                        ChecklistRow(
                            definition: definition,
                            isChecked: isChecked(definition),
                            onToggle: { toggle(definition) }
                        )
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)

                Spacer()

                // Progress indicator
                if !completedIds.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(completedIds.count) of \(definitions.count) completed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Done button
                Button(action: finish) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if showCelebration {
                    QuickCheckCelebrationOverlay(onComplete: { dismiss() })
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // Pre-populate with already completed items
            for definition in definitions {
                if interventionService.isCompletedToday(definition.id) {
                    completedIds.insert(definition.id)
                }
            }
        }
    }

    private var definitions: [InterventionDefinition] {
        interventionIds.compactMap { id in
            interventionService.enabledInterventions()
                .first { $0.interventionId == id }
                .flatMap { interventionService.interventionDefinition(for: $0) }
        }
    }

    private func isChecked(_ definition: InterventionDefinition) -> Bool {
        completedIds.contains(definition.id)
    }

    private func toggle(_ definition: InterventionDefinition) {
        if completedIds.contains(definition.id) {
            completedIds.remove(definition.id)
            interventionService.removeLastCompletion(for: definition.id)
        } else {
            completedIds.insert(definition.id)
            // Log completion based on tracking type
            switch definition.trackingType {
            case .binary:
                interventionService.logCompletion(interventionId: definition.id, value: .binary(true))
            case .counter:
                interventionService.logCompletion(interventionId: definition.id, value: .count(1))
            case .timer:
                interventionService.logCompletion(interventionId: definition.id, value: .duration(0))
            default:
                interventionService.logCompletion(interventionId: definition.id, value: .binary(true))
            }
        }
    }

    private func finish() {
        if !completedIds.isEmpty {
            showCelebration = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Checklist Row

private struct ChecklistRow: View {
    let definition: InterventionDefinition
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Emoji
                Text(definition.emoji)
                    .font(.title2)

                // Name
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isChecked ? .secondary : .primary)
                        .strikethrough(isChecked)

                    if !isChecked {
                        Text(definition.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Checkbox
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isChecked ? .green : .secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Celebration Overlay

private struct QuickCheckCelebrationOverlay: View {
    let onComplete: () -> Void
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    @State private var particleOffsets: [(x: CGFloat, y: CGFloat)] = Array(repeating: (0, 0), count: 8)

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    // Checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                        .scaleEffect(scale)

                    // Burst particles
                    ForEach(0..<8, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 16))
                            .foregroundColor(.green.opacity(0.8))
                            .offset(x: particleOffsets[i].x, y: particleOffsets[i].y)
                            .opacity(opacity)
                    }
                }

                Text("All done!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .opacity(opacity)
            }
        }
        .onAppear {
            // Animate checkmark in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.2
            }

            // Animate particles outward
            withAnimation(.easeOut(duration: 0.5)) {
                for i in 0..<8 {
                    let angle = Double(i) * (360.0 / 8.0) * .pi / 180
                    particleOffsets[i] = (cos(angle) * 70, sin(angle) * 70)
                }
            }

            // Settle scale
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.15)) {
                    scale = 1.0
                }
            }

            // Fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
            }

            // Complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                onComplete()
            }
        }
    }
}

#Preview {
    QuickCheckModal(
        interventionIds: ["tongue_posture", "jaw_relaxation"],
        interventionService: InterventionService()
    )
}
