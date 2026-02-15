//
//  CapacityDialView.swift
//  Skywalker
//
//  OpenJaw - Time + Energy capacity picker for filtering daily plan
//

import SwiftUI

struct CapacityDialView: View {
    @Binding var selectedMinutes: Int?
    @Binding var selectedEnergy: EnergyLevel?
    var onConfirm: (UserCapacity) -> Void

    // Animation state
    @State private var animateIn = false

    private var canConfirm: Bool {
        selectedMinutes != nil && selectedEnergy != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Time selection
            VStack(alignment: .leading, spacing: 10) {
                Text("How much time do you have?")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    ForEach(UserCapacity.timeOptions, id: \.self) { minutes in
                        TimeChipButton(
                            minutes: minutes,
                            isSelected: selectedMinutes == minutes,
                            action: { selectedMinutes = minutes }
                        )
                    }
                }
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)

            // Energy selection
            VStack(alignment: .leading, spacing: 10) {
                Text("What's your energy like?")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    ForEach(EnergyLevel.allCases, id: \.self) { level in
                        EnergyChipButton(
                            level: level,
                            isSelected: selectedEnergy == level,
                            action: { selectedEnergy = level }
                        )
                    }
                }
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)
            .animation(.easeOut(duration: 0.3).delay(0.1), value: animateIn)

            // Confirm button
            Button(action: confirmSelection) {
                HStack {
                    Text("Show my plan")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canConfirm ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(canConfirm ? .white : .secondary)
                .cornerRadius(12)
            }
            .disabled(!canConfirm)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)
            .animation(.easeOut(duration: 0.3).delay(0.2), value: animateIn)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                animateIn = true
            }
        }
    }

    private func confirmSelection() {
        guard let minutes = selectedMinutes, let energy = selectedEnergy else { return }
        let capacity = UserCapacity(availableMinutes: minutes, maxEnergy: energy)
        onConfirm(capacity)
    }
}

// MARK: - Time Chip Button

private struct TimeChipButton: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(UserCapacity.timeDisplayText(minutes: minutes))
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("min")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(minWidth: 50, minHeight: 50)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Energy Chip Button

private struct EnergyChipButton: View {
    let level: EnergyLevel
    let isSelected: Bool
    let action: () -> Void

    private var displayText: String {
        switch level {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    private var emoji: String {
        switch level {
        case .low: return "🌙"
        case .medium: return "☀️"
        case .high: return "⚡️"
        }
    }

    private var accentColor: Color {
        switch level {
        case .low: return .purple
        case .medium: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.callout)
                Text(displayText)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    VStack {
        Spacer()
        CapacityDialView(
            selectedMinutes: .constant(15),
            selectedEnergy: .constant(.medium),
            onConfirm: { _ in }
        )
        .padding()
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
