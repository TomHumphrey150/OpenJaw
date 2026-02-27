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
    let selectedSkinID: TelocareSkinID

    @State private var navigationPath = NavigationPath()
    @State private var filterMode: InputFilterMode
    @State private var gardenSelection = GardenHierarchySelection.all
    private let gardenHierarchyBuilder = GardenHierarchyBuilder()
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
        self.selectedSkinID = selectedSkinID
        _filterMode = State(initialValue: inputs.contains(where: \.isActive) ? .pending : .available)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: TelocareTheme.Spacing.md, pinnedViews: [.sectionHeaders]) {
                    Section {
                        gardenContentSection
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

    private var breadcrumbSegments: [GardenBreadcrumbSegment] {
        var segments = [GardenBreadcrumbSegment(depth: 0, title: "All Gardens")]

        for (index, nodeID) in resolvedNodePath.enumerated() {
            let title = gardenHierarchyBuilder.nodeTitle(
                for: nodeID,
                in: graphData
            )
            segments.append(
                GardenBreadcrumbSegment(
                    depth: index + 1,
                    title: title
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
            GardenBreadcrumbView(
                segments: breadcrumbSegments,
                canGoBack: !resolvedNodePath.isEmpty,
                onGoBack: goBackOneLevel,
                onSelectDepth: selectBreadcrumbDepth
            )
            filterPillsSection
                .accessibilityIdentifier(AccessibilityID.exploreInputsPinnedHeader)
        }
        .id(resolvedNodePath)
        .padding(.horizontal, TelocareTheme.Spacing.md)
        .padding(.top, TelocareTheme.Spacing.md)
        .padding(.bottom, TelocareTheme.Spacing.xs)
        .background(TelocareTheme.sand)
    }

    @ViewBuilder
    private var gardenContentSection: some View {
        VStack(spacing: TelocareTheme.Spacing.sm) {
            if !hierarchyCurrentClusters.isEmpty {
                gardenGrid
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if let currentLeafCluster {
                CurrentGardenCardView(cluster: currentLeafCluster)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: TelocareTheme.Spacing.xs) {
                Text("\(checkedTodayCount) of \(hierarchyFilteredActiveInputs.count) habits completed today")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)

                if checkedTodayCount == hierarchyFilteredActiveInputs.count && !hierarchyFilteredActiveInputs.isEmpty {
                    Label("All done!", systemImage: "checkmark.circle.fill")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.success)
                }
            }
        }
        .padding(.horizontal, TelocareTheme.Spacing.md)
        .padding(.top, TelocareTheme.Spacing.xs)
        .accessibilityIdentifier(AccessibilityID.exploreInputsGardenHierarchy)
        .animation(.easeInOut(duration: 0.2), value: resolvedNodePath)
    }

    private var gardenGrid: some View {
        GardenGridView(
            clusters: hierarchyCurrentClusters,
            selectedNodeID: resolvedNodePath.last,
            onSelectNode: selectSubGarden
        )
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
        hierarchyFilteredInputs.filter(\.isActive)
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
        let source = hierarchyFilteredInputs
        switch mode {
        case .pending:
            return source.filter { $0.isActive && !$0.isCheckedToday }.count
        case .completed:
            return source.filter { $0.isActive && $0.isCheckedToday }.count
        case .available:
            return source.filter { !$0.isActive }.count
        }
    }

    // MARK: - Inputs Content

    @ViewBuilder
    private var inputsListSection: some View {
        if filteredInputs.isEmpty {
            emptyStatePlaceholder
                .padding(.horizontal, TelocareTheme.Spacing.md)
                .padding(.bottom, TelocareTheme.Spacing.md)
        } else {
            LazyVStack(spacing: TelocareTheme.Spacing.sm) {
                if filterMode != .available && !nextBestActions.isEmpty {
                    nextBestActionsSection
                        .accessibilityIdentifier(AccessibilityID.exploreInputsNextBestActions)
                }

                ForEach(filteredInputs) { input in
                    InputCard(
                        input: input,
                        onToggle: { toggleInputCheckedToday(input.id) },
                        onIncrementDose: { onIncrementDose(input.id) },
                        onToggleActive: { onToggleActive(input.id) },
                        onShowDetails: { showInputDetail(input) }
                    )
                }
            }
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.bottom, TelocareTheme.Spacing.md)
        }
    }

    /// Inputs sorted by impact score (most useful first), filtered by selected garden
    private var sortedInputs: [InputStatus] {
        InputScoring.sortedByImpact(inputs: hierarchyFilteredInputs, graphData: graphData)
    }

    private var filteredInputs: [InputStatus] {
        switch filterMode {
        case .pending:
            return sortedInputs.filter { $0.isActive && !$0.isCheckedToday }
        case .completed:
            return sortedInputs.filter { $0.isActive && $0.isCheckedToday }
        case .available:
            return sortedInputs.filter { !$0.isActive }
        }
    }

    private var visibleInputs: [InputStatus] {
        sortedInputs.filter(\.isActive)
    }

    private var shouldShowStreakBadge: Bool {
        visibleInputs.contains { currentStreakLength(for: $0) >= 2 }
    }

    private var nextBestActions: [InputStatus] {
        let source = hierarchyFilteredInputs
        let defaultOrderByID = Dictionary(uniqueKeysWithValues: source.enumerated().map { ($1.id, $0) })
        return source
            .filter { $0.isActive && !$0.isCheckedToday }
            .sorted { lhs, rhs in
                let lhsDueNow = isDueNow(lhs)
                let rhsDueNow = isDueNow(rhs)
                if lhsDueNow != rhsDueNow {
                    return lhsDueNow && !rhsDueNow
                }

                let lhsEvidenceRank = evidenceRank(for: lhs.evidenceLevel)
                let rhsEvidenceRank = evidenceRank(for: rhs.evidenceLevel)
                if lhsEvidenceRank != rhsEvidenceRank {
                    return lhsEvidenceRank > rhsEvidenceRank
                }

                let lhsOrder = defaultOrderByID[lhs.id] ?? Int.max
                let rhsOrder = defaultOrderByID[rhs.id] ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(3)
            .map { $0 }
    }

    @ViewBuilder
    private var nextBestActionsSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
                WarmSectionHeader(
                    title: "Next Best Actions",
                    subtitle: "Top priorities right now"
                )
                Text("Selected from active habits not completed today. Ranking: due now, stronger evidence, then your default habit order.")
                    .font(TelocareTheme.Typography.caption)
                    .foregroundStyle(TelocareTheme.warmGray)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(nextBestActions) { input in
                    nextBestActionRow(for: input)

                    if input.id != nextBestActions.last?.id {
                        Divider()
                            .background(TelocareTheme.peach)
                    }
                }
            }
        }
    }

    private func toggleInputCheckedToday(_ inputID: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            onToggleCheckedToday(inputID)
        }
    }

    @ViewBuilder
    private func nextBestActionRow(for input: InputStatus) -> some View {
        HStack(spacing: TelocareTheme.Spacing.sm) {
            nextBestActionPrimaryControl(for: input)

            Button {
                showInputDetail(input)
            } label: {
                HStack(spacing: TelocareTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                        Text(input.name)
                            .font(TelocareTheme.Typography.headline)
                            .foregroundStyle(TelocareTheme.charcoal)
                        Text(nextBestActionReason(for: input))
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(TelocareTheme.muted)
                }
                .padding(.vertical, TelocareTheme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func nextBestActionPrimaryControl(for input: InputStatus) -> some View {
        switch input.trackingMode {
        case .binary:
            Button {
                toggleInputCheckedToday(input.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.small, style: .continuous)
                        .fill(input.isCheckedToday ? TelocareTheme.coral : TelocareTheme.peach)
                    if input.isCheckedToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Check \(input.name)")
            .accessibilityHint("Marks this habit as done for today.")
        case .dose:
            if let doseState = input.doseState {
                Button {
                    onIncrementDose(input.id)
                } label: {
                    DoseCompletionRing(state: doseState, size: 34, lineWidth: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increment \(input.name)")
                .accessibilityValue("\(doseSummaryText(for: doseState)).")
                .accessibilityHint("Adds one increment toward today's goal.")
            }
        }
    }

    private func nextBestActionReason(for input: InputStatus) -> String {
        let priority = priorityRank(for: input)
        let dueText = isDueNow(input) ? "due now" : "scheduled for \(scheduleDescription(for: input))"
        let evidenceText = evidenceDescription(for: input.evidenceLevel)
        return "Priority \(priority): \(dueText); \(evidenceText)."
    }

    private func isDueNow(_ input: InputStatus) -> Bool {
        let schedule = Set(input.timeOfDay)
        if schedule.isEmpty || schedule.contains(.anytime) {
            return true
        }

        return schedule.contains(currentDaySegment)
    }

    private func priorityRank(for input: InputStatus) -> Int {
        guard let index = nextBestActions.firstIndex(where: { $0.id == input.id }) else {
            return 0
        }

        return index + 1
    }

    private func scheduleDescription(for input: InputStatus) -> String {
        let schedule = Set(input.timeOfDay)
        if schedule.isEmpty || schedule.contains(.anytime) {
            return "any time"
        }

        let orderedSegments: [InterventionTimeOfDay] = [.morning, .afternoon, .evening, .preBed]
        let labels = orderedSegments
            .filter { schedule.contains($0) }
            .map(daySegmentLabel(for:))

        return labels.joined(separator: ", ")
    }

    private func daySegmentLabel(for segment: InterventionTimeOfDay) -> String {
        switch segment {
        case .morning:
            return "morning"
        case .afternoon:
            return "afternoon"
        case .evening:
            return "evening"
        case .preBed:
            return "pre-bed"
        case .anytime:
            return "any time"
        }
    }

    private func evidenceDescription(for evidenceLevel: String?) -> String {
        switch evidenceRank(for: evidenceLevel) {
        case 3:
            return "high evidence"
        case 2:
            return "moderate evidence"
        case 1:
            return "emerging evidence"
        default:
            return "no evidence rating"
        }
    }

    private func doseSummaryText(for state: InputDoseState) -> String {
        "\(formattedDoseValue(state.value))/\(formattedDoseValue(state.goal)) \(state.unit.displayName)"
    }

    private func formattedDoseValue(_ value: Double) -> String {
        let roundedValue = value.rounded()
        if abs(roundedValue - value) < 0.0001 {
            return String(Int(roundedValue))
        }

        return String(format: "%.1f", value)
    }

    private var currentDaySegment: InterventionTimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .preBed
        }
    }

    private func evidenceRank(for evidenceLevel: String?) -> Int {
        guard let normalized = evidenceLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return 0
        }

        if normalized.contains("robust") || normalized.contains("strong") || normalized.contains("high") {
            return 3
        }
        if normalized.contains("moderate") || normalized.contains("medium") {
            return 2
        }
        if normalized.contains("preliminary") || normalized.contains("emerging") || normalized.contains("low") {
            return 1
        }

        return 0
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
            Text(emptyStateMessage)
                .font(TelocareTheme.Typography.body)
                .foregroundStyle(TelocareTheme.warmGray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(TelocareTheme.Spacing.xl)
    }

    private var emptyStateMessage: String {
        switch filterMode {
        case .pending:
            return "No active interventions left for today."
        case .completed:
            return "Nothing completed yet today.\nTap an intervention to make progress."
        case .available:
            return "No available interventions."
        }
    }
}

// MARK: - Filter Mode

private enum InputFilterMode: CaseIterable {
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

// MARK: - Input Card

private struct InputCard: View {
    let input: InputStatus
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
