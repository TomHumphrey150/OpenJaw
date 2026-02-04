//
//  InterventionCardView.swift
//  Skywalker
//
//  OpenJaw - Individual intervention card for home screen
//

import SwiftUI

struct InterventionCardView: View {
    let definition: InterventionDefinition
    let todayCount: Int
    let isCompletedToday: Bool
    var streak: Int = 0
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Evidence tier dots (●●● = strong, ●●○ = moderate, ●○○ = lower)
                tierDots

                // Icon (using emoji from definition)
                Text(definition.emoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(evidenceTierColor.opacity(0.15))
                    .cornerRadius(8)

                // Name and status
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Streak badge (only show for streaks > 1)
                if streak > 1 {
                    HStack(spacing: 2) {
                        Text("\u{1F525}")  // fire emoji
                            .font(.caption)
                        Text("\(streak)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }

                // Info button - opens detail view
                Button(action: onLongPress) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.body)
                }
                .buttonStyle(BorderlessButtonStyle())

                // Completion indicator
                if definition.trackingType == .counter {
                    Text("\(todayCount)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(todayCount > 0 ? evidenceTierColor : .secondary)
                } else if isCompletedToday {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            .padding(12)
            .background(roiBackground)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture {
            onLongPress()
        }
    }

    // MARK: - Evidence Tier Visual Indicator

    /// Dot indicator showing evidence strength: ●●● = strong, ●●○ = moderate, ●○○ = lower
    private var tierDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < filledDotCount ? evidenceTierColor : Color.gray.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }

    /// Number of filled dots based on evidence tier
    private var filledDotCount: Int {
        switch definition.tier {
        case .strong: return 3   // ●●●
        case .moderate: return 2 // ●●○
        case .lower: return 1    // ●○○
        }
    }

    /// Color for evidence tier indicator
    private var evidenceTierColor: Color {
        switch definition.tier {
        case .strong: return .green
        case .moderate: return .blue
        case .lower: return .orange
        }
    }

    private var roiBackground: Color {
        guard let roi = definition.roiTier else {
            return Color.secondary.opacity(0.08)
        }

        let base = Color.green
        let opacity: Double

        switch roi {
        case "A": opacity = 0.28
        case "B": opacity = 0.22
        case "C": opacity = 0.16
        case "D": opacity = 0.12
        case "E": opacity = 0.09
        default: opacity = 0.08
        }

        return base.opacity(opacity)
    }

    private var statusText: String {
        switch definition.trackingType {
        case .counter:
            return "\(todayCount) today"
        case .binary, .checklist:
            return isCompletedToday ? "Done today" : "Not done"
        case .timer:
            return isCompletedToday ? "Done today" : "Not started"
        case .automatic:
            return "Automatic"
        case .appointment:
            return "Scheduled"
        }
    }
}

// MARK: - Info Popover

private struct InfoPopover: View {
    let definition: InterventionDefinition
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Text(definition.emoji)
                            .font(.system(size: 48))
                        VStack(alignment: .leading) {
                            Text(definition.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            if let level = definition.evidenceLevel {
                                Text(level)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Why this habit?
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why this habit?")
                            .font(.headline)

                        if let summary = definition.evidenceSummary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // ROI Info
                    if let roi = definition.roiTier {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Return on Investment")
                                .font(.headline)

                            HStack {
                                roiTierBadge(roi)
                                Spacer()
                                if let cost = definition.costRange {
                                    Text(cost)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let ease = definition.easeScore {
                                HStack {
                                    Text("Ease of implementation:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(ease)/10")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Why this habit?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
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

        let description: String = {
            switch tier {
            case "A": return "Excellent ROI"
            case "B": return "Good ROI"
            case "C": return "Moderate ROI"
            case "D": return "Lower ROI"
            case "E": return "Limited Evidence"
            default: return ""
            }
        }()

        HStack {
            Text("Tier \(tier)")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.2))
                .foregroundColor(color)
                .cornerRadius(4)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        InterventionCardView(
            definition: InterventionDefinition(
                id: "tongue_posture",
                name: "Tongue Posture",
                emoji: "👅",
                icon: "mouth.fill",
                description: "Keep tongue on roof of mouth",
                tier: .moderate,
                frequency: .hourly,
                trackingType: .counter,
                isRemindable: true,
                evidenceLevel: "Low-Moderate",
                evidenceSummary: "Clinical experience supports jaw positioning. Most effective for awake bruxism.",
                roiTier: "A",
                easeScore: 10,
                costRange: "$0"
            ),
            todayCount: 3,
            isCompletedToday: true,
            streak: 5,
            onTap: {},
            onLongPress: {}
        )

        InterventionCardView(
            definition: InterventionDefinition(
                id: "night_guard",
                name: "Night Guard",
                emoji: "🌙",
                icon: "moon.fill",
                description: "Wear your night guard",
                tier: .strong,
                frequency: .daily,
                trackingType: .binary,
                isRemindable: false
            ),
            todayCount: 0,
            isCompletedToday: false,
            streak: 0,
            onTap: {},
            onLongPress: {}
        )
    }
    .padding()
}
