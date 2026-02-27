import SwiftUI

struct ExploreChatScreen: View {
    @Binding var draft: String
    let feedback: String
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
            "Why is my jaw sore?",
            "What can I try tonight?",
            "Explain my progress",
            "Best interventions for me"
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            messages.append(ChatMessage(
                id: UUID(),
                content: "I appreciate your question! The AI backend isn't connected yet, but once it is, I'll be able to help analyze your sleep data and provide personalized recommendations.",
                isFromUser: false,
                timestamp: Date()
            ))
        }
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
