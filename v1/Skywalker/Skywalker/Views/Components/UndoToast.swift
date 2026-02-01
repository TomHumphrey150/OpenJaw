//
//  UndoToast.swift
//  Skywalker
//
//  OpenJaw - Floating toast with undo action and countdown timer
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let duration: TimeInterval
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var progress: CGFloat = 1.0
    @State private var isVisible = true

    init(
        message: String,
        duration: TimeInterval = 4.0,
        onUndo: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.duration = duration
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                // Message
                Text(message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Spacer()

                // Undo button
                Button(action: handleUndo) {
                    Text("Undo")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                startCountdown()
            }
        }
    }

    private func startCountdown() {
        withAnimation(.linear(duration: duration)) {
            progress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if isVisible {
                dismissToast()
            }
        }
    }

    private func handleUndo() {
        onUndo()
        dismissToast()
    }

    private func dismissToast() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        onDismiss()
    }
}

// MARK: - Toast Overlay Modifier

struct UndoToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let duration: TimeInterval
    let onUndo: () -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if isPresented {
                UndoToast(
                    message: message,
                    duration: duration,
                    onUndo: onUndo,
                    onDismiss: { isPresented = false }
                )
                .padding(.bottom, 16)
            }
        }
        .animation(.spring(response: 0.3), value: isPresented)
    }
}

extension View {
    func undoToast(
        isPresented: Binding<Bool>,
        message: String,
        duration: TimeInterval = 4.0,
        onUndo: @escaping () -> Void
    ) -> some View {
        modifier(UndoToastModifier(
            isPresented: isPresented,
            message: message,
            duration: duration,
            onUndo: onUndo
        ))
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            UndoToast(
                message: "Completed Tongue Posture",
                duration: 4.0,
                onUndo: { print("Undo tapped") },
                onDismiss: { print("Dismissed") }
            )
            .padding(.bottom, 32)
        }
    }
}
