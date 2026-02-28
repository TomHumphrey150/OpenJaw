import SwiftUI

struct ExploreChatScreen: View {
    @Binding var draft: String
    let feedback: String
    let pendingGraphPatchPreview: GraphPatchPreview?
    let pendingGraphPatchConflicts: [GraphPatchConflict]
    let pendingGraphPatchConflictResolutions: [Int: GraphConflictResolutionChoice]
    let checkpointVersions: [String]
    let graphVersion: String?
    let onSetConflictResolution: (Int, GraphConflictResolutionChoice) -> Void
    let onApplyPendingPatch: () -> Void
    let onDismissPendingPatch: () -> Void
    let onRollbackGraphVersion: (String) -> Void
    let onSend: () -> Void
    let selectedSkinID: TelocareSkinID

    @State private var messages: [ChatMessage] = [
        ChatMessage(
            id: UUID(),
            content: "Hi there! I'm your sleep wellness assistant. I can help you understand your sleep patterns, suggest interventions, and answer questions about TMD management. What would you like to explore today?",
            isFromUser: false,
            timestamp: Date()
        )
    ]
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: TelocareTheme.Spacing.md) {
                            if let graphVersion {
                                graphVersionBadge(graphVersion)
                            }

                            if let pendingGraphPatchPreview {
                                patchPreviewCard(preview: pendingGraphPatchPreview)
                            }

                            if !checkpointVersions.isEmpty {
                                checkpointHistoryCard
                            }

                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(TelocareTheme.Spacing.md)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: feedback) { _, nextFeedback in
                        appendAssistantMessage(nextFeedback)
                    }
                }

                if messages.count <= 2 {
                    suggestedPromptsSection
                }

                chatInputBar
            }
            .background(TelocareTheme.sand.ignoresSafeArea())
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(TelocareTheme.coral)
        .animation(.easeInOut(duration: 0.2), value: selectedSkinID)
    }

    // MARK: - Suggested Prompts

    @ViewBuilder
    private var suggestedPromptsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TelocareTheme.Spacing.sm) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button {
                        sendMessage(prompt)
                    } label: {
                        Text(prompt)
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.coral)
                            .padding(.horizontal, TelocareTheme.Spacing.md)
                            .padding(.vertical, TelocareTheme.Spacing.sm)
                            .background(TelocareTheme.peach)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TelocareTheme.Spacing.md)
            .padding(.bottom, TelocareTheme.Spacing.sm)
        }
    }

    private var suggestedPrompts: [String] {
        [
            "Export graph",
            "Apply patch",
            "Rollback graph-",
            "Show latest graph changes"
        ]
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(TelocareTheme.peach)

            HStack(spacing: TelocareTheme.Spacing.sm) {
                TextField("Ask anything about your sleep...", text: $draft, axis: .vertical)
                    .font(TelocareTheme.Typography.body)
                    .padding(.horizontal, TelocareTheme.Spacing.md)
                    .padding(.vertical, TelocareTheme.Spacing.sm)
                    .background(TelocareTheme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous))
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .accessibilityIdentifier(AccessibilityID.exploreChatInput)

                Button {
                    sendMessage(draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(draft.isEmpty ? TelocareTheme.muted : TelocareTheme.coral)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(AccessibilityID.exploreChatSendButton)
            }
            .padding(TelocareTheme.Spacing.md)
            .background(TelocareTheme.sand)
        }
    }

    private func sendMessage(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(id: UUID(), content: trimmed, isFromUser: true, timestamp: Date()))
        draft = ""
        onSend()
    }

    @ViewBuilder
    private func graphVersionBadge(_ version: String) -> some View {
        HStack {
            Label("Graph \(version)", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                .font(TelocareTheme.Typography.caption)
                .foregroundStyle(TelocareTheme.warmGray)
            Spacer()
        }
        .padding(.horizontal, TelocareTheme.Spacing.md)
    }

    @ViewBuilder
    private func patchPreviewCard(preview: GraphPatchPreview) -> some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            Text("Patch Preview")
                .font(TelocareTheme.Typography.headline)
                .foregroundStyle(TelocareTheme.charcoal)
                .accessibilityIdentifier(AccessibilityID.exploreChatGraphPreview)

            if !preview.summaryLines.isEmpty {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                    ForEach(preview.summaryLines, id: \.self) { line in
                        Text("• \(line)")
                            .font(TelocareTheme.Typography.caption)
                            .foregroundStyle(TelocareTheme.warmGray)
                    }
                }
            }

            if !preview.envelope.explanations.isEmpty {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                    ForEach(Array(preview.envelope.explanations.enumerated()), id: \.offset) { _, explanation in
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text(explanation.title)
                                .font(TelocareTheme.Typography.caption)
                                .foregroundStyle(TelocareTheme.charcoal)
                            Text(explanation.details)
                                .font(TelocareTheme.Typography.small)
                                .foregroundStyle(TelocareTheme.warmGray)
                        }
                    }
                }
            }

            if !pendingGraphPatchConflicts.isEmpty {
                VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                    Text("Conflict Review")
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.charcoal)

                    ForEach(pendingGraphPatchConflicts) { conflict in
                        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.xs) {
                            Text(conflict.message)
                                .font(TelocareTheme.Typography.small)
                                .foregroundStyle(TelocareTheme.warmGray)

                            HStack(spacing: TelocareTheme.Spacing.sm) {
                                conflictResolutionButton(
                                    title: "Local",
                                    isSelected: pendingGraphPatchConflictResolutions[conflict.operationIndex] == .local,
                                    action: { onSetConflictResolution(conflict.operationIndex, .local) }
                                )
                                conflictResolutionButton(
                                    title: "Server",
                                    isSelected: pendingGraphPatchConflictResolutions[conflict.operationIndex] == .server,
                                    action: { onSetConflictResolution(conflict.operationIndex, .server) }
                                )
                            }
                        }
                        .padding(.vertical, TelocareTheme.Spacing.xs)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.exploreChatGraphConflicts)
            }

            HStack(spacing: TelocareTheme.Spacing.sm) {
                Button("Dismiss") {
                    onDismissPendingPatch()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityID.exploreChatGraphDismissButton)

                Button("Apply Patch") {
                    onApplyPendingPatch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(patchApplyIsBlocked)
                .accessibilityIdentifier(AccessibilityID.exploreChatGraphApplyButton)
            }
        }
        .padding(TelocareTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous)
                .fill(TelocareTheme.cream)
        )
    }

    @ViewBuilder
    private var checkpointHistoryCard: some View {
        VStack(alignment: .leading, spacing: TelocareTheme.Spacing.sm) {
            Text("Graph Checkpoints")
                .font(TelocareTheme.Typography.headline)
                .foregroundStyle(TelocareTheme.charcoal)

            ForEach(checkpointVersions, id: \.self) { version in
                HStack {
                    Text(version)
                        .font(TelocareTheme.Typography.caption)
                        .foregroundStyle(TelocareTheme.warmGray)
                    Spacer()
                    Button("Rollback") {
                        onRollbackGraphVersion(version)
                    }
                    .font(TelocareTheme.Typography.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(TelocareTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous)
                .fill(TelocareTheme.cream)
        )
        .accessibilityIdentifier(AccessibilityID.exploreChatGraphCheckpoints)
    }

    @ViewBuilder
    private func conflictResolutionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(TelocareTheme.Typography.caption)
                .frame(minWidth: 68, minHeight: 44)
                .foregroundStyle(isSelected ? Color.white : TelocareTheme.coral)
                .background(
                    RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
                        .fill(isSelected ? TelocareTheme.coral : TelocareTheme.peach)
                )
        }
        .buttonStyle(.plain)
    }

    private var patchApplyIsBlocked: Bool {
        if pendingGraphPatchConflicts.isEmpty {
            return false
        }
        let conflictIndices = Set(pendingGraphPatchConflicts.map(\.operationIndex))
        return conflictIndices.isSubset(of: Set(pendingGraphPatchConflictResolutions.keys)) == false
    }

    private func appendAssistantMessage(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if messages.last?.content == trimmed, messages.last?.isFromUser == false {
            return
        }

        messages.append(
            ChatMessage(
                id: UUID(),
                content: trimmed,
                isFromUser: false,
                timestamp: Date()
            )
        )
    }
}

// MARK: - Chat Message Model

private struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 60) }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: TelocareTheme.Spacing.xs) {
                Text(message.content)
                    .font(TelocareTheme.Typography.body)
                    .foregroundStyle(message.isFromUser ? .white : TelocareTheme.charcoal)
                    .padding(TelocareTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.large, style: .continuous)
                            .fill(message.isFromUser ? TelocareTheme.coral : TelocareTheme.cream)
                    )

                Text(formattedTime)
                    .font(TelocareTheme.Typography.small)
                    .foregroundStyle(TelocareTheme.muted)
            }

            if !message.isFromUser { Spacer(minLength: 60) }
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
