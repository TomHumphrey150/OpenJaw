//
//  FocusBlockHeaderView.swift
//  Skywalker
//
//  OpenJaw - Collapsed header for focus blocks with peek preview
//

import SwiftUI

struct FocusBlockHeaderView: View {
    let block: FocusBlock
    let isExpanded: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // State indicator
                stateIndicator

                // Section name and time
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(stateLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(stateColor)
                            .textCase(.uppercase)

                        Text(block.section.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    // Summary line
                    summaryText
                }

                Spacer()

                // Progress or chevron
                HStack(spacing: 8) {
                    if block.isFullyCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        // Progress badge
                        Text("\(block.completedCount)/\(block.totalCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 10, height: 10)
    }

    private var stateLabel: String {
        switch block.state {
        case .now: return "Now"
        case .next: return "Next"
        case .later: return "Later"
        case .completed: return "Done"
        }
    }

    private var stateColor: Color {
        switch block.state {
        case .now: return .blue
        case .next: return .orange
        case .later: return .secondary
        case .completed: return .green
        }
    }

    // MARK: - Summary Text

    @ViewBuilder
    private var summaryText: some View {
        if block.isFullyCompleted {
            Text("Great job!")
                .font(.caption)
                .foregroundColor(.green)
        } else if block.state == .now {
            Text("~\(block.remainingDurationMinutes) min remaining")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            // Peek ahead - show first few items
            let remaining = block.items.prefix(2).map { $0.1.name }
            Text(remaining.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        // Note: Preview requires proper mock data
        Text("FocusBlockHeaderView Preview")
            .foregroundColor(.secondary)
    }
    .padding()
}
