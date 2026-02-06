//
//  DailyPlanTab.swift
//  Skywalker
//
//  OpenJaw - Main tab for daily interventions/habits
//

import SwiftUI

struct DailyPlanTab: View {
    @Bindable var interventionService: InterventionService
    @Bindable var routineService: RoutineService
    var onShowUndoToast: (InterventionDefinition) -> Void

    // Capacity state - reset each session (per user preference: "Just ask each time")
    @State private var selectedMinutes: Int?
    @State private var selectedEnergy: EnergyLevel?
    @State private var userCapacity: UserCapacity?

    // Track when capacity was last set (for potential time-block reset)
    @State private var lastCapacitySetTime: Date?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Text("🦷")
                            .font(.title2)
                        Text("OpenJaw")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 20)

                    // Capacity Dial - shown when no capacity set for this session
                    if userCapacity == nil {
                        CapacityDialView(
                            selectedMinutes: $selectedMinutes,
                            selectedEnergy: $selectedEnergy,
                            onConfirm: { capacity in
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    userCapacity = capacity
                                    lastCapacitySetTime = Date()
                                }
                            }
                        )
                        .padding(.horizontal)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    } else {
                        // Capacity summary with edit button
                        capacitySummaryView
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Daily habits / interventions
                    if userCapacity != nil {
                        // Show Focus Stack when capacity is set
                        FocusStackView(
                            interventionService: interventionService,
                            routineService: routineService,
                            capacity: userCapacity,
                            onShowUndoToast: onShowUndoToast
                        )
                        .padding(.horizontal)
                    } else {
                        // Show standard view when no capacity set (fallback)
                        InterventionsSectionView(
                            interventionService: interventionService,
                            routineService: routineService,
                            onShowUndoToast: onShowUndoToast
                        )
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // MARK: - Capacity Summary View

    private var capacitySummaryView: some View {
        HStack {
            if let capacity = userCapacity {
                HStack(spacing: 12) {
                    // Time badge
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text("\(capacity.availableMinutes) min")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(8)

                    // Energy badge
                    HStack(spacing: 4) {
                        Text(energyEmoji(for: capacity.maxEnergy))
                            .font(.caption)
                        Text(energyText(for: capacity.maxEnergy))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(energyColor(for: capacity.maxEnergy).opacity(0.15))
                    .foregroundColor(energyColor(for: capacity.maxEnergy))
                    .cornerRadius(8)
                }

                Spacer()

                // Edit button
                Button(action: resetCapacity) {
                    Text("Change")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func resetCapacity() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            userCapacity = nil
            // Keep selected values so user doesn't have to start over
        }
    }

    private func energyEmoji(for level: EnergyLevel) -> String {
        switch level {
        case .low: return "🌙"
        case .medium: return "☀️"
        case .high: return "⚡️"
        }
    }

    private func energyText(for level: EnergyLevel) -> String {
        switch level {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    private func energyColor(for level: EnergyLevel) -> Color {
        switch level {
        case .low: return .purple
        case .medium: return .orange
        case .high: return .red
        }
    }
}

#Preview {
    DailyPlanTab(
        interventionService: InterventionService(),
        routineService: RoutineService(),
        onShowUndoToast: { _ in }
    )
}
