import SwiftUI
import UIKit

struct ExploreInputsScreen: View {
    let inputs: [InputStatus]
    let graphData: CausalGraphData
    let onToggleCheckedToday: (String) -> Void
    let onIncrementDose: (String) -> Void
    let onDecrementDose: (String) -> Void
    let onResetDose: (String) -> Void
    let onUpdateDoseSettings: (String, Double, Double) -> Void
    let onConnectAppleHealth: (String) -> Void
    let onDisconnectAppleHealth: (String) -> Void
    let onRefreshAppleHealth: (String) async -> Void
    let onRefreshAllAppleHealth: () async -> Void
    let onToggleActive: (String) -> Void
    let planningMetadataByInterventionID: [String: HabitPlanningMetadata]
    let pillarAssignments: [PillarAssignment]
    let orderedPillars: [HealthPillarDefinition]
    let habitRungStatusByInterventionID: [String: HabitRungStatus]
    let plannedInterventionIDs: Set<String>
    let onRecordHigherRungCompletion: (String, String) -> Void
    let selectedSkinID: TelocareSkinID

    @State private var navigationPath = NavigationPath()
    @State private var filterMode: InputFilterMode
    @State private var gardenSelection = GardenHierarchySelection.all
    @State private var pendingHigherRungCompletion: HigherRungCompletionPrompt?
    private let gardenHierarchyBuilder = GardenHierarchyBuilder()
    private let pillarInputsSectionBuilder = PillarInputsSectionBuilder()
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(
        inputs: [InputStatus],
        graphData: CausalGraphData,
        onToggleCheckedToday: @escaping (String) -> Void,
        onIncrementDose: @escaping (String) -> Void,
        onDecrementDose: @escaping (String) -> Void,
        onResetDose: @escaping (String) -> Void,
        onUpdateDoseSettings: @escaping (String, Double, Double) -> Void,
        onConnectAppleHealth: @escaping (String) -> Void,
        onDisconnectAppleHealth: @escaping (String) -> Void,
        onRefreshAppleHealth: @escaping (String) async -> Void,
        onRefreshAllAppleHealth: @escaping () async -> Void,
        onToggleActive: @escaping (String) -> Void,
        planningMetadataByInterventionID: [String: HabitPlanningMetadata],
        pillarAssignments: [PillarAssignment],
        orderedPillars: [HealthPillarDefinition],
        habitRungStatusByInterventionID: [String: HabitRungStatus],
        plannedInterventionIDs: Set<String>,
        onRecordHigherRungCompletion: @escaping (String, String) -> Void,
        selectedSkinID: TelocareSkinID
    ) {
        self.inputs = inputs
        self.graphData = graphData
        self.onToggleCheckedToday = onToggleCheckedToday
        self.onIncrementDose = onIncrementDose
        self.onDecrementDose = onDecrementDose
        self.onResetDose = onResetDose
        self.onUpdateDoseSettings = onUpdateDoseSettings
        self.onConnectAppleHealth = onConnectAppleHealth
        self.onDisconnectAppleHealth = onDisconnectAppleHealth
        self.onRefreshAppleHealth = onRefreshAppleHealth
        self.onRefreshAllAppleHealth = onRefreshAllAppleHealth
        self.onToggleActive = onToggleActive
        self.planningMetadataByInterventionID = planningMetadataByInterventionID
        self.pillarAssignments = pillarAssignments
        self.orderedPillars = orderedPillars
        self.habitRungStatusByInterventionID = habitRungStatusByInterventionID
        self.plannedInterventionIDs = plannedInterventionIDs
        self.onRecordHigherRungCompletion = onRecordHigherRungCompletion
        self.selectedSkinID = selectedSkinID
        _filterMode = State(initialValue: inputs.contains(where: \.isActive) ? .pending : .available)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: TelocareTheme.Spacing.md, pinnedViews: [.sectionHeaders]) {
                    Section {
                        pillarOverviewSection
                        inputsListSection
                    } header: {
                        pinnedHeaderSection
                    }
                }
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .refreshable {
                await onRefreshAllAppleHealth()
            }
            .accessibilityIdentifier(AccessibilityID.exploreInputsUnifiedScroll)
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { inputID in
                if let input = inputStatus(for: inputID) {
                    InputDetailView(
                        input: input,
                        graphData: graphData,
                        onIncrementDose: onIncrementDose,
                        onDecrementDose: onDecrementDose,
                        onResetDose: onResetDose,
                        onUpdateDoseSettings: onUpdateDoseSettings,
                        onConnectAppleHealth: onConnectAppleHealth,
                        onDisconnectAppleHealth: onDisconnectAppleHealth,
                        onRefreshAppleHealth: onRefreshAppleHealth,
                        onToggleActive: onToggleActive
                    )
                    .accessibilityIdentifier(AccessibilityID.exploreInputDetailSheet)
                } else {
                    ContentUnavailableView("Intervention unavailable", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
        .confirmationDialog(
            "Did more than suggested?",
            isPresented: Binding(
                get: { pendingHigherRungCompletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingHigherRungCompletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let prompt = pendingHigherRungCompletion {
                ForEach(prompt.higherRungs) { rung in
                    Button("I did \(rung.title)") {
                        onRecordHigherRungCompletion(prompt.interventionID, rung.id)
                        pendingHigherRungCompletion = nil
                    }
                }
                Button("Keep suggested rung", role: .cancel) {
                    pendingHigherRungCompletion = nil
                }
            }
        }
    }

    private func showInputDetail(_ input: InputStatus) {
        navigationPath.append(input.id)
    }

    private func inputStatus(for inputID: String) -> InputStatus? {
        inputs.first { $0.id == inputID }
    }

    // MARK: - Garden Overview

    private var gardenHierarchyResult: GardenHierarchyBuildResult {
        gardenHierarchyBuilder.build(
            inputs: inputs,
            graphData: graphData,
            selection: gardenSelection
        )
    }

    private var resolvedNodePath: [String] {
        gardenHierarchyResult.resolvedNodePath
    }

    private var resolvedClusterPath: [GardenClusterSnapshot] {
        gardenHierarchyResult.resolvedClusterPath
    }

    private var breadcrumbSegments: [GardenBreadcrumbSegment] {
        var segments = [GardenBreadcrumbSegment(depth: 0, title: "All Gardens")]

        for (index, cluster) in resolvedClusterPath.enumerated() {
            segments.append(
                GardenBreadcrumbSegment(
                    depth: index + 1,
                    title: cluster.title
                )
            )
        }

        return segments
    }

    private var hierarchyCurrentLevel: GardenHierarchyLevel? {
        gardenHierarchyResult.levels.last
    }

    private var hierarchyCurrentClusters: [GardenClusterSnapshot] {
        hierarchyCurrentLevel?.clusters ?? []
    }

    private var currentLeafCluster: GardenClusterSnapshot? {
        guard !resolvedNodePath.isEmpty else {
            return nil
        }
        guard hierarchyCurrentClusters.isEmpty else {
            return nil
        }

        return gardenHierarchyBuilder.leafCluster(
            nodePath: resolvedNodePath,
            filteredInputs: hierarchyFilteredInputs,
            graphData: graphData
        )
    }

    @ViewBuilder
    private var pinnedHeaderSection: some View {
        VStack(spacing: TelocareTheme.Spacing.sm) {
            HStack {
                Text("Health Pillars")
                    .font(TelocareTheme.Typography.headline)
                    .foregroundStyle(TelocareTheme.charcoal)
                Spacer()
            }
            filterPillsSection
                .accessibilityIdentifier(AccessibilityID.exploreInputsPinnedHeader)
        }
        .padding(.horizontal, TelocareTheme.Spacing.md)
        .padding(.top, TelocareTheme.Spacing.md)
        .padding(.bottom, TelocareTheme.Spacing.xs)
        .background(TelocareTheme.sand)
    }

    @ViewBuilder
    private var pillarOverviewSection: some View {
        VStack(spacing: TelocareTheme.Spacing.sm) {
            HStack(spacing: TelocareTheme.Spacing.xs) {
                Text("\(checkedTodayCount) of \(activeInputCount) habits completed today")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)

                if checkedTodayCount == activeInputCount && activeInputCount > 0 {
                    Label("All done!", systemImage: "checkmark.circle.fill")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.success)
                }
            }
        }
        .padding(.horizontal, TelocareTheme.Spacing.md)
        .padding(.top, TelocareTheme.Spacing.xs)
        .accessibilityIdentifier(AccessibilityID.exploreInputsPillarOverview)
    }

    private func selectBreadcrumbDepth(_ depth: Int) {
        if depth <= 0 {
            gardenSelection = .all
            return
        }

        let keepCount = min(depth, resolvedNodePath.count)
        gardenSelection.selectedNodePath = Array(resolvedNodePath.prefix(keepCount))
    }

    private func goBackOneLevel() {
        guard !resolvedNodePath.isEmpty else {
            return
        }

        gardenSelection.selectedNodePath = Array(resolvedNodePath.dropLast())
    }

    private func selectSubGarden(_ nodeID: String) {
        gardenSelection.selectedNodePath = resolvedNodePath + [nodeID]
    }

    private var hierarchyFilteredInputs: [InputStatus] {
        gardenHierarchyResult.filteredInputs
    }

    private var hierarchyFilteredActiveInputs: [InputStatus] {
        inputs.filter(\.isActive)
    }

    private var activeInputCount: Int {
        hierarchyFilteredActiveInputs.count
    }

    private var checkedTodayCount: Int {
        hierarchyFilteredActiveInputs.filter(\.isCheckedToday).count
    }

    private var overallCompletion: Double {
        guard !hierarchyFilteredActiveInputs.isEmpty else { return 0 }
        return Double(checkedTodayCount) / Double(hierarchyFilteredActiveInputs.count)
    }

    // MARK: - Filter Pills

    @ViewBuilder
    private var filterPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                ForEach(InputFilterMode.allCases, id: \.self) { mode in
                    FilterPill(
                        title: mode.title,
                        count: countFor(mode),
                        isSelected: filterMode == mode,
                        action: { filterMode = mode },
                        accessibilityIdentifier: filterAccessibilityIdentifier(for: mode)
                    )
                }
            }
            .padding(.vertical, TelocareTheme.Spacing.sm)
        }
    }

    private func filterAccessibilityIdentifier(for mode: InputFilterMode) -> String {
        switch mode {
        case .pending:
            return AccessibilityID.exploreInputsFilterPending
        case .completed:
            return AccessibilityID.exploreInputsFilterCompleted
        case .available:
            return AccessibilityID.exploreInputsFilterAvailable
        }
    }

    private func countFor(_ mode: InputFilterMode) -> Int {
        let source = inputs
        switch mode {
        case .pending:
            return source.filter { $0.isActive && !$0.isCheckedToday }.count
        case .completed:
            return source.filter { $0.isActive && $0.isCheckedToday }.count
        case .available:
            return source.filter { !$0.isActive }.count
        }
    }

    private var emptyStateGuidance: ExploreInputsEmptyStateGuidance {
        ExploreInputsEmptyStateGuidance(
            filterMode: filterMode,
            availableCount: countFor(.available)
        )
    }

    // MARK: - Inputs Content

    @ViewBuilder
    private var inputsListSection: some View {
        if filteredPillarSections.isEmpty {
            emptyStatePlaceholder
                .padding(.horizontal, TelocareTheme.Spacing.md)
                .padding(.bottom, TelocareTheme.Spacing.md)
        } else {
            LazyVStack(spacing: TelocareTheme.Spacing.sm) {
                ForEach(filteredPillarSections) { section in
                    WarmCard {
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                            HStack {
                                Text(section.title)
                                    .font(TelocareTheme.Typography.headline)
                                    .foregroundStyle(TelocareTheme.charcoal)
                                Spacer()
                                Text("\(section.inputs.count)")
                                    .font(TelocareTheme.Typography.caption)
                                    .foregroundStyle(TelocareTheme.warmGray)
                            }
                            .accessibilityIdentifier(AccessibilityID.exploreInputsPillarChip(pillar: section.pillar.id))

                            ForEach(section.inputs) { input in
                                InputCard(
                                    input: input,
                                    planningMetadata: planningMetadataByInterventionID[input.id],
                                    rungStatus: habitRungStatusByInterventionID[input.id],
                                    isPlannedToday: plannedInterventionIDs.contains(input.id),
                                    onToggle: { handleCompletionTap(for: input) },
                                    onIncrementDose: { onIncrementDose(input.id) },
                                    onToggleActive: { onToggleActive(input.id) },
                                    onShowDetails: { showInputDetail(input) }
                                )

                                if input.id != section.inputs.last?.id {
                                    Divider()
                                        .background(TelocareTheme.peach)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.exploreInputsPillarSection(pillar: section.pillar.id))
                }
            }
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.bottom, TelocareTheme.Spacing.md)
        }
    }

    /// Inputs sorted by impact score (most useful first)
    private var sortedInputs: [InputStatus] {
        InputScoring.sortedByImpact(inputs: inputs, graphData: graphData)
    }

    private var filteredPillarSections: [PillarInputsSection] {
        let sections = pillarInputsSectionBuilder.build(
            inputs: sortedInputs,
            planningMetadataByInterventionID: planningMetadataByInterventionID,
            pillarAssignments: pillarAssignments,
            orderedPillars: orderedPillars
        )

        return sections.compactMap { section in
            let filtered = filteredInputs(from: section.inputs)
            if filtered.isEmpty {
                return nil
            }
            return PillarInputsSection(
                pillar: section.pillar,
                title: section.title,
                inputs: filtered
            )
        }
    }

    private func filteredInputs(from source: [InputStatus]) -> [InputStatus] {
        switch filterMode {
        case .pending:
            return source.filter { $0.isActive && !$0.isCheckedToday }
        case .completed:
            return source.filter { $0.isActive && $0.isCheckedToday }
        case .available:
            return source.filter { !$0.isActive }
        }
    }

    private var visibleInputs: [InputStatus] {
        sortedInputs.filter(\.isActive)
    }

    private var shouldShowStreakBadge: Bool {
        visibleInputs.contains { currentStreakLength(for: $0) >= 2 }
    }

    private func toggleInputCheckedToday(_ inputID: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            onToggleCheckedToday(inputID)
        }
    }

    private func handleCompletionTap(for input: InputStatus) {
        let wasChecked = input.isCheckedToday
        toggleInputCheckedToday(input.id)

        guard !wasChecked else {
            return
        }
        guard let rungStatus = habitRungStatusByInterventionID[input.id] else {
            return
        }
        guard rungStatus.canReportHigherCompletion else {
            return
        }

        pendingHigherRungCompletion = HigherRungCompletionPrompt(
            interventionID: input.id,
            higherRungs: rungStatus.higherRungs
        )
    }

    private func currentStreakLength(for input: InputStatus) -> Int {
        guard input.isActive else {
            return 0
        }
        guard input.isCheckedToday else {
            return 0
        }

        var completedDays = Set(input.completionEvents.compactMap { completionDayKey(for: $0.occurredAt) })
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let todayKey = localDayKey(for: startOfToday, calendar: calendar)
        completedDays.insert(todayKey)

        var streakLength = 0
        var dayOffset = 0
        while let date = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday) {
            let dayKey = localDayKey(for: date, calendar: calendar)
            guard completedDays.contains(dayKey) else {
                break
            }

            streakLength += 1
            dayOffset += 1
        }

        return streakLength
    }

    private func completionDayKey(for timestamp: String) -> String? {
        if let date = Self.iso8601WithFractionalSeconds.date(from: timestamp) {
            return localDayKey(for: date, calendar: .current)
        }
        if let date = Self.iso8601WithoutFractionalSeconds.date(from: timestamp) {
            return localDayKey(for: date, calendar: .current)
        }
        return nil
    }

    private func localDayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    @ViewBuilder
    private var emptyStatePlaceholder: some View {
        VStack(spacing: TelocareTheme.Spacing.md) {
            Spacer()
            Image(systemName: filterMode == .completed ? "checkmark.circle" : "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(TelocareTheme.muted)
            Text(emptyStateGuidance.message)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.warmGray)
                .multilineTextAlignment(.center)
            if emptyStateGuidance.shouldShowAvailableNudge {
                Button {
                    filterMode = .available
                } label: {
                    HStack(spacing: TelocareTheme.Spacing.xs) {
                        Text("See available habits")
                        Image(systemName: "arrow.right")
                    }
                    .font(TelocareTheme.Typography.body)
                    .padding(.horizontal, TelocareTheme.Spacing.md)
                    .padding(.vertical, TelocareTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.exploreInputsEmptySwitchToAvailable)
            }
            Spacer()
        }
        .padding(TelocareTheme.Spacing.xl)
    }
}

// MARK: - Filter Mode

enum InputFilterMode: CaseIterable {
    case pending, completed, available

    var title: String {
        switch self {
        case .pending:
            return "To do"
        case .completed:
            return "Done"
        case .available:
            return "Available"
        }
    }
}

struct ExploreInputsEmptyStateGuidance: Equatable {
    let filterMode: InputFilterMode
    let availableCount: Int

    var message: String {
        switch filterMode {
        case .pending:
            if shouldShowAvailableNudge {
                return "No active habits here right now.\nYou can add habits from Available."
            }
            return "No active interventions left for today."
        case .completed:
            return "Nothing completed yet today.\nTap an intervention to make progress."
        case .available:
            return "No available interventions."
        }
    }

    var shouldShowAvailableNudge: Bool {
        filterMode != .available && availableCount > 0
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    let accessibilityIdentifier: String

    var body: some View {
        Button(action: action) {
            HStack(spacing: TelocareTheme.Spacing.xs) {
                Text(title)
                Text("\(count)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : TelocareTheme.muted.opacity(0.3))
                    .clipShape(Capsule())
            }
            .font(TelocareTheme.Typography.caption)
            .foregroundStyle(isSelected ? .white : TelocareTheme.charcoal)
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.vertical, TelocareTheme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? TelocareTheme.coral : TelocareTheme.cream)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct HigherRungCompletionPrompt {
    let interventionID: String
    let higherRungs: [HabitLadderRung]
}

// MARK: - Input Card

private struct InputCard: View {
    let input: InputStatus
    let planningMetadata: HabitPlanningMetadata?
    let rungStatus: HabitRungStatus?
    let isPlannedToday: Bool
    let onToggle: () -> Void
    let onIncrementDose: () -> Void
    let onToggleActive: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        WarmCard(padding: 0) {
            HStack(spacing: 0) {
                primaryControl
                    .padding(.leading, TelocareTheme.Spacing.sm)
                    .padding(.vertical, TelocareTheme.Spacing.sm)

                Button(action: onShowDetails) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.name)
                                .font(TelocareTheme.Typography.headline)
                                .foregroundStyle(input.isActive && input.isCheckedToday && input.trackingMode == .binary ? TelocareTheme.muted : TelocareTheme.charcoal)
                                .strikethrough(input.isActive && input.isCheckedToday && input.trackingMode == .binary)

                            if let planningMetadata {
                                HStack(spacing: TelocareTheme.Spacing.xs) {
                                    Text(planningMetadata.pillars.first?.displayName ?? "General")
                                        .font(TelocareTheme.Typography.small)
                                        .foregroundStyle(TelocareTheme.warmGray)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(TelocareTheme.peach.opacity(0.45))
                                        .clipShape(Capsule())

                                    if planningMetadata.isAcute {
                                        Text("Acute")
                                            .font(TelocareTheme.Typography.small)
                                            .foregroundStyle(TelocareTheme.coral)
                                    } else if planningMetadata.isFoundation {
                                        Text("Foundation")
                                            .font(TelocareTheme.Typography.small)
                                            .foregroundStyle(TelocareTheme.success)
                                    }

                                    if isPlannedToday {
                                        Text("Planned")
                                            .font(TelocareTheme.Typography.small)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(TelocareTheme.charcoal)
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            if input.isActive, let rungStatus {
                                Text("Rung \(rungStatus.currentRungTitle) (target \(rungStatus.targetRungTitle))")
                                    .font(TelocareTheme.Typography.small)
                                    .foregroundStyle(TelocareTheme.warmGray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: TelocareTheme.Spacing.sm) {
                                if input.trackingMode == .binary {
                                    WeeklyProgressBar(completion: input.completion)
                                } else if let doseState = input.doseState {
                                    Text(doseSummaryText(for: doseState))
                                        .font(TelocareTheme.Typography.caption)
                                        .foregroundStyle(TelocareTheme.warmGray)
                                }

                                if let evidence = input.evidenceLevel {
                                    EvidenceBadge(level: evidence)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(TelocareTheme.muted)
                    }
                    .padding(.horizontal, TelocareTheme.Spacing.sm)
                    .padding(.vertical, TelocareTheme.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if !input.isActive {
            Button(action: onToggleActive) {
                ZStack {
                    RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                        .fill(TelocareTheme.cream)
                    RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                        .stroke(TelocareTheme.coral, lineWidth: 1.5)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TelocareTheme.coral)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start tracking \(input.name)")
            .accessibilityHint("Adds this intervention to your active list.")
        } else {
            switch input.trackingMode {
            case .binary:
                Button(action: onToggle) {
                    ZStack {
                        RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                            .fill(input.isCheckedToday ? TelocareTheme.coral : TelocareTheme.peach)
                        if input.isCheckedToday {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(input.isCheckedToday ? "Uncheck \(input.name)" : "Check \(input.name)")
                .accessibilityHint("Marks this intervention as done for today.")

            case .dose:
                if let doseState = input.doseState {
                    Button(action: onIncrementDose) {
                        DoseCompletionRing(state: doseState, size: 34, lineWidth: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.exploreInputDoseIncrement)
                    .accessibilityLabel("Increment \(input.name)")
                    .accessibilityValue("\(doseSummaryText(for: doseState)).")
                    .accessibilityHint("Adds one increment toward today's goal.")
                }
            }
        }
    }

    private func doseSummaryText(for state: InputDoseState) -> String {
        "\(formatted(state.value))/\(formatted(state.goal)) \(state.unit.displayName)"
    }

    private func formatted(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
    }
}

struct DoseCompletionRing: View {
    let state: InputDoseState
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(TelocareTheme.peach, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: state.completionClamped)
                .stroke(
                    state.isGoalMet ? TelocareTheme.success : TelocareTheme.coral,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((state.completionRaw * 100).rounded()))%")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(TelocareTheme.charcoal)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Weekly Progress Bar

private struct WeeklyProgressBar: View {
    let completion: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < Int(completion * 7) ? TelocareTheme.coral : TelocareTheme.peach)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Evidence Badge

struct EvidenceBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(TelocareTheme.Typography.small)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch level.lowercased() {
        case "strong", "high":
            return TelocareTheme.success
        case "moderate", "medium":
            return TelocareTheme.warmOrange
        default:
            return TelocareTheme.muted
        }
    }
}
