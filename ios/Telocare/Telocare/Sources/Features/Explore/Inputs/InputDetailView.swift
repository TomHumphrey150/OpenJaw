import SwiftUI

struct InputDetailView: View {
    let input: InputStatus
    let graphData: CausalGraphData
    let onIncrementDose: (String) -> Void
    let onDecrementDose: (String) -> Void
    let onResetDose: (String) -> Void
    let onUpdateDoseSettings: (String, Double, Double) -> Void
    let onConnectAppleHealth: (String) -> Void
    let onDisconnectAppleHealth: (String) -> Void
    let onRefreshAppleHealth: (String) async -> Void
    let onToggleActive: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dailyGoalText: String = ""
    @State private var incrementText: String = ""
    @State private var liveDoseState: InputDoseState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                Text(input.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(TelocareTheme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)

                appleHealthCard
                statusCard
                InputCompletionHistoryCard(events: input.completionEvents)
                doseCard
                evidenceCard

                if input.detailedDescription != nil {
                    descriptionCard
                }

                if input.externalLink != nil {
                    linkCard
                }

                trackingCard
            }
            .padding(TelocareTheme.Spacing.md)
        }
        .background(TelocareTheme.sand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let doseState = input.doseState {
                liveDoseState = doseState
                dailyGoalText = formattedDoseValue(doseState.goal)
                incrementText = formattedDoseValue(doseState.increment)
            }
        }
        .onChange(of: input.doseState) { _, updatedDoseState in
            liveDoseState = updatedDoseState
        }
    }

    // MARK: - Tracking Card

    @ViewBuilder
    private var trackingCard: some View {
        WarmCard {
            Button {
                onToggleActive(input.id)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: input.isActive ? "minus.circle" : "plus.circle")
                        .font(.system(size: 16))
                    Text(input.isActive ? "Stop tracking this intervention" : "Start tracking this intervention")
                        .font(TelocareTheme.Typography.body)
                    Spacer()
                }
                .foregroundStyle(input.isActive ? TelocareTheme.warmGray : TelocareTheme.coral)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Dose Card

    @ViewBuilder
    private var appleHealthCard: some View {
        if input.trackingMode == .dose, let appleHealthState = input.appleHealthState, appleHealthState.available {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Apple Health")

                    if appleHealthState.connected {
                        DetailRow(label: "Connection", value: "Connected")
                        DetailRow(label: "Sync status", value: appleHealthStatusText(appleHealthState.syncStatus))

                        if let healthValue = appleHealthState.todayHealthValue, let doseState = currentDoseState {
                            DetailRow(
                                label: primaryAppleHealthValueLabel(for: appleHealthState),
                                value: "\(formattedDoseValue(healthValue)) \(doseState.unit.displayName)"
                            )

                            if
                                let referenceHealthValue = appleHealthState.referenceTodayHealthValue,
                                let referenceLabel = appleHealthState.referenceTodayHealthValueLabel
                            {
                                DetailRow(
                                    label: referenceLabel,
                                    value: "\(formattedDoseValue(referenceHealthValue)) \(doseState.unit.displayName)"
                                )
                            }
                        } else {
                            Text("No Apple Health data found today. Using app dose entries.")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                        }

                        if let lastSyncAt = appleHealthState.lastSyncAt {
                            DetailRow(label: "Last sync", value: lastSyncAt)
                        }

                        HStack(spacing: TelocareTheme.Spacing.sm) {
                            Button("Refresh Apple Health") {
                                Task {
                                    await onRefreshAppleHealth(input.id)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(TelocareTheme.coral)
                            .accessibilityIdentifier(AccessibilityID.exploreInputAppleHealthRefresh)
                            .accessibilityHint("Refreshes today's Apple Health value for this intervention.")

                            Button("Disconnect") {
                                onDisconnectAppleHealth(input.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(TelocareTheme.warmGray)
                            .accessibilityIdentifier(AccessibilityID.exploreInputAppleHealthDisconnect)
                            .accessibilityHint("Stops Apple Health sync for this intervention.")
                        }
                    } else {
                        Text("Connect to Apple Health to read today's value automatically.")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)

                        Button("Connect to Apple Health") {
                            onConnectAppleHealth(input.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TelocareTheme.coral)
                        .accessibilityIdentifier(AccessibilityID.exploreInputAppleHealthConnect)
                        .accessibilityHint("Requests read access for this intervention's Apple Health data.")
                    }
                }
            }
        }
    }

    private func appleHealthStatusText(_ status: AppleHealthSyncStatus) -> String {
        switch status {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .noData:
            return "No data today"
        case .failed:
            return "Sync failed"
        }
    }

    private func primaryAppleHealthValueLabel(for state: InputAppleHealthState) -> String {
        guard state.config?.identifier == .moderateWorkoutMinutes else {
            return "Today in Apple Health"
        }

        return "Moderate minutes (goal metric)"
    }

    @ViewBuilder
    private var doseCard: some View {
        if input.trackingMode == .dose, let doseState = currentDoseState {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Dose Tracking")

                    HStack(spacing: TelocareTheme.Spacing.md) {
                        DoseCompletionRing(state: doseState, size: 60, lineWidth: 6)
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text("Today")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                            Text("\(formattedDoseValue(doseState.value)) / \(formattedDoseValue(doseState.goal)) \(doseState.unit.displayName)")
                                .font(TelocareTheme.Typography.body)
                                .foregroundStyle(TelocareTheme.charcoal)
                            Text("Increment: \(formattedDoseValue(doseState.increment)) \(doseState.unit.displayName)")
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.warmGray)
                        }
                        Spacer()
                    }

                    HStack(spacing: TelocareTheme.Spacing.sm) {
                        doseActionButton(
                            title: "−",
                            systemImage: "minus.circle.fill",
                            accessibilityID: AccessibilityID.exploreInputDoseDecrement
                        ) {
                            applyLocalDoseDelta(-doseState.increment)
                            onDecrementDose(input.id)
                        }
                        doseActionButton(
                            title: "+",
                            systemImage: "plus.circle.fill",
                            accessibilityID: AccessibilityID.exploreInputDoseIncrement
                        ) {
                            applyLocalDoseDelta(doseState.increment)
                            onIncrementDose(input.id)
                        }
                        doseActionButton(
                            title: "Reset",
                            systemImage: "arrow.counterclockwise.circle.fill",
                            accessibilityID: AccessibilityID.exploreInputDoseReset
                        ) {
                            applyLocalDoseReset()
                            onResetDose(input.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                        Text("Daily Goal and Increment")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)

                        HStack(spacing: TelocareTheme.Spacing.sm) {
                            TextField("Goal", text: $dailyGoalText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Daily goal")

                            TextField("Increment", text: $incrementText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Dose increment")
                        }

                        Button("Save Dose Settings") {
                            saveDoseSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TelocareTheme.coral)
                        .accessibilityIdentifier(AccessibilityID.exploreInputDoseSaveSettings)
                        .accessibilityHint("Saves this intervention goal and increment.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func doseActionButton(
        title: String,
        systemImage: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(TelocareTheme.Typography.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(TelocareTheme.coral)
        .accessibilityIdentifier(accessibilityID)
    }

    private func saveDoseSettings() {
        guard let goal = parsePositiveNumber(dailyGoalText), let increment = parsePositiveNumber(incrementText) else {
            return
        }

        if let doseState = currentDoseState {
            liveDoseState = InputDoseState(
                manualValue: doseState.manualValue,
                healthValue: doseState.healthValue,
                goal: goal,
                increment: increment,
                unit: doseState.unit
            )
        }

        onUpdateDoseSettings(input.id, goal, increment)
    }

    private var currentDoseState: InputDoseState? {
        liveDoseState ?? input.doseState
    }

    private func applyLocalDoseDelta(_ delta: Double) {
        guard let doseState = currentDoseState else {
            return
        }

        let nextManualValue = max(0, doseState.manualValue + delta)
        liveDoseState = InputDoseState(
            manualValue: nextManualValue,
            healthValue: doseState.healthValue,
            goal: doseState.goal,
            increment: doseState.increment,
            unit: doseState.unit
        )
    }

    private func applyLocalDoseReset() {
        guard let doseState = currentDoseState else {
            return
        }

        liveDoseState = InputDoseState(
            manualValue: 0,
            healthValue: doseState.healthValue,
            goal: doseState.goal,
            increment: doseState.increment,
            unit: doseState.unit
        )
    }

    private func parsePositiveNumber(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }

        return value
    }

    private func formattedDoseValue(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
    }

    private var currentStatusText: String {
        guard input.trackingMode == .dose, let doseState = currentDoseState else {
            return input.statusText
        }

        let completionPercent = Int((doseState.completionRaw * 100).rounded())
        return "\(formattedDoseValue(doseState.value)) of \(formattedDoseValue(doseState.goal)) \(doseState.unit.displayName) (\(completionPercent)%)"
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Status")

                DetailRow(label: "Tracking", value: input.isActive ? "Active" : "Available")
                DetailRow(label: "Status", value: currentStatusText)
                if input.trackingMode == .binary {
                    DetailRow(label: "7-day completion", value: "\(Int((input.completion * 100).rounded()))%")
                    DetailRow(label: "Checked today", value: input.isCheckedToday ? "Yes" : "No")
                } else if let doseState = currentDoseState {
                    DetailRow(label: "Goal reached", value: doseState.isGoalMet ? "Yes" : "No")
                    DetailRow(label: "Current dose", value: "\(formattedDoseValue(doseState.value)) \(doseState.unit.displayName)")
                    DetailRow(label: "Daily goal", value: "\(formattedDoseValue(doseState.goal)) \(doseState.unit.displayName)")
                }

                if let classification = input.classificationText {
                    DetailRow(label: "Classification", value: classification)
                }
            }
        }
    }

    // MARK: - Evidence Card

    @ViewBuilder
    private var evidenceCard: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(title: "Evidence")

                if let level = input.evidenceLevel ?? graphNodeData?.tooltip?.evidence {
                    HStack {
                        Text("Level")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                        Spacer()
                        EvidenceBadge(level: level)
                    }
                }

                if let summary = input.evidenceSummary ?? graphNodeData?.tooltip?.mechanism {
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Text("Summary")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                        Text(summary)
                            .font(TelocareTheme.Typography.body)
                            .foregroundStyle(TelocareTheme.charcoal)
                    }
                }

                if !input.citationIDs.isEmpty {
                    DetailRow(label: "Citations", value: input.citationIDs.joined(separator: ", "))
                }

                if let stat = graphNodeData?.tooltip?.stat {
                    DetailRow(label: "Statistic", value: stat)
                }
            }
        }
    }

    // MARK: - Description Card

    @ViewBuilder
    private var descriptionCard: some View {
        if let description = input.detailedDescription {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Description")
                    Text(description)
                        .font(TelocareTheme.Typography.body)
                        .foregroundStyle(TelocareTheme.charcoal)
                }
            }
        }
    }

    // MARK: - Link Card

    @ViewBuilder
    private var linkCard: some View {
        if let link = input.externalLink {
            WarmCard {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                    WarmSectionHeader(title: "Reference")
                    if let url = URL(string: link) {
                        Link(destination: url) {
                            HStack {
                                Text(link)
                                    .font(TelocareTheme.Typography.body)
                                    .foregroundStyle(TelocareTheme.coral)
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(TelocareTheme.coral)
                            }
                        }
                    } else {
                        Text(link)
                            .font(TelocareTheme.Typography.body)
                            .foregroundStyle(TelocareTheme.charcoal)
                    }
                }
            }
        }
    }

    private var graphNodeData: GraphNodeData? {
        let nodeID = input.graphNodeID ?? input.id
        return graphData.nodes.first { $0.data.id == nodeID }?.data
    }
}

