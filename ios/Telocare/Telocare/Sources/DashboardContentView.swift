import SwiftUI

struct DashboardContentView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    let selectedSkinID: TelocareSkinID
    let isMuseEnabled: Bool

    var body: some View {
        ZStack {
            ExploreTabShell(
                viewModel: viewModel,
                selectedSkinID: selectedSkinID,
                isMuseSessionEnabled: isMuseEnabled
            )

            VStack {
                HStack {
                    Spacer()
                    ProfileAvatarButton(mode: viewModel.mode) {
                        viewModel.openProfileSheet()
                    }
                }
                Spacer()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.handleAppMovedToBackground()
                return
            }

            if newPhase == .active {
                Task {
                    await viewModel.refreshAllConnectedAppleHealth(trigger: .automatic)
                }
            }
        }
    }
}

struct GlobalLensSheet: View {
    let mode: HealthLensMode
    let selection: PillarLensSelection
    let corePillars: [HealthPillarDefinition]
    let userDefinedPillars: [HealthPillarDefinition]
    let userDefinedPillarRows: [UserDefinedPillar]
    let onSelectAll: () -> Void
    let onSelectNone: () -> Void
    let onTogglePillar: (HealthPillar) -> Void
    let onCreatePillar: (String, String) -> Void
    let onRenamePillar: (String, String) -> Void
    let onSetPillarArchived: (String, Bool) -> Void
    let onClose: () -> Void

    @State private var isManagerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.md) {
                    Text("Pillars")
                        .font(TelocareTheme.Typography.headline)
                        .foregroundStyle(TelocareTheme.charcoal)

                    HStack(spacing: TelocareTheme.Spacing.sm) {
                        Button {
                            onSelectAll()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selection.isAllSelected ? "checkmark.circle.fill" : "circle")
                                Text("All")
                            }
                            .font(TelocareTheme.Typography.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.exploreInputsLensAll)

                        Button {
                            onSelectNone()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isNoneSelected ? "checkmark.circle.fill" : "circle")
                                Text("None")
                            }
                            .font(TelocareTheme.Typography.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(AccessibilityID.exploreInputsLensNone)
                    }

                    Divider()
                        .background(TelocareTheme.peach)

                    Text("Core pillars")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)

                    ForEach(corePillars) { pillar in
                        pillarRow(for: pillar)
                    }

                    if !userDefinedPillars.isEmpty {
                        Divider()
                            .background(TelocareTheme.peach)

                        Text("Your pillars")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)

                        ForEach(userDefinedPillars) { pillar in
                            pillarRow(for: pillar)
                        }
                    }

                    Button("Manage Pillars") {
                        isManagerPresented = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityID.exploreInputsLensManagePillars)
                }
                .padding(TelocareTheme.Spacing.md)
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Global Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onClose()
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.globalLensSheet)
        .sheet(isPresented: $isManagerPresented) {
            PillarManagerSheet(
                userDefinedPillars: userDefinedPillarRows,
                onCreatePillar: onCreatePillar,
                onRenamePillar: onRenamePillar,
                onSetPillarArchived: onSetPillarArchived
            )
        }
    }

    @ViewBuilder
    private func pillarRow(for pillar: HealthPillarDefinition) -> some View {
        Button {
            onTogglePillar(pillar.id)
        } label: {
            HStack {
                Text(pillar.title)
                    .font(TelocareTheme.Typography.body)
                    .foregroundStyle(TelocareTheme.charcoal)
                Spacer()
                Image(systemName: isPillarSelected(pillar.id.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(TelocareTheme.success)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.exploreInputsLensPillar(pillar: pillar.id.rawValue))
    }

    private var selectedPillarIDs: Set<String> {
        Set(selection.selectedPillarIDs.map(\.id))
    }

    private func isPillarSelected(_ pillarID: String) -> Bool {
        if selection.isAllSelected {
            return true
        }
        return selectedPillarIDs.contains(pillarID)
    }

    private var isNoneSelected: Bool {
        mode == .pillars && !selection.isAllSelected && selection.selectedPillarIDs.isEmpty
    }
}

private struct PillarManagerSheet: View {
    let userDefinedPillars: [UserDefinedPillar]
    let onCreatePillar: (String, String) -> Void
    let onRenamePillar: (String, String) -> Void
    let onSetPillarArchived: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateID = "neck"
    @State private var newPillarTitle = ""
    @State private var editingPillarID: String?
    @State private var editingTitle = ""

    private let templates: [(id: String, title: String)] = [
        ("neck", "Neck"),
        ("reflux", "Reflux"),
        ("sleep-breathing", "Sleep Breathing"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Create from template") {
                    Picker("Template", selection: $selectedTemplateID) {
                        ForEach(templates, id: \.id) { template in
                            Text(template.title).tag(template.id)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Pillar title", text: $newPillarTitle)
                        .textInputAutocapitalization(.words)

                    Button("Create pillar") {
                        onCreatePillar(selectedTemplateID, newPillarTitle)
                        newPillarTitle = ""
                    }
                    .disabled(newPillarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Your pillars") {
                    if userDefinedPillars.isEmpty {
                        Text("No custom pillars yet.")
                            .foregroundStyle(TelocareTheme.warmGray)
                    } else {
                        ForEach(userDefinedPillars) { pillar in
                            VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                                if editingPillarID == pillar.id {
                                    TextField("Title", text: $editingTitle)
                                        .textInputAutocapitalization(.words)
                                    HStack(spacing: TelocareTheme.Spacing.sm) {
                                        Button("Save") {
                                            onRenamePillar(pillar.id, editingTitle)
                                            editingPillarID = nil
                                        }
                                        .disabled(editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        Button("Cancel", role: .cancel) {
                                            editingPillarID = nil
                                        }
                                    }
                                } else {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pillar.title)
                                            Text(pillar.templateId)
                                                .font(.caption)
                                                .foregroundStyle(TelocareTheme.warmGray)
                                        }
                                        Spacer()
                                        Button("Rename") {
                                            editingPillarID = pillar.id
                                            editingTitle = pillar.title
                                        }
                                    }

                                    Button(pillar.isArchived ? "Restore" : "Archive") {
                                        onSetPillarArchived(pillar.id, !pillar.isArchived)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Pillars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
