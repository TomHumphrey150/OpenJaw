//
//  BlockCompletionModal.swift
//  Skywalker
//
//  OpenJaw - Celebration modal when completing a time block
//

import SwiftUI

struct BlockCompletionModal: View {
    let blockName: String
    let completedCount: Int
    let totalCount: Int
    let streakDays: Int?
    var onContinue: () -> Void

    @State private var showConfetti = false
    @State private var animateIn = false

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on background tap
                    onContinue()
                }

            // Content card
            VStack(spacing: 24) {
                // Celebration icon with animation
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .scaleEffect(animateIn ? 1.2 : 0.8)
                        .opacity(animateIn ? 0.5 : 0)

                    Circle()
                        .fill(Color.green)
                        .frame(width: 72, height: 72)

                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(animateIn ? 1 : 0)
                }

                // Title
                Text("\(blockName) Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)

                // Stats
                VStack(spacing: 8) {
                    Text("You finished \(completedCount)/\(totalCount) items")
                        .font(.body)
                        .foregroundColor(.secondary)

                    if let streak = streakDays, streak > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("\(streak)-day streak!")
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 10)

                // Continue button
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 10)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
            .scaleEffect(animateIn ? 1 : 0.9)

            // Confetti overlay
            if showConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            // Entrance animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animateIn = true
            }

            // Trigger confetti
            showConfetti = true

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}

// MARK: - View Modifier

struct BlockCompletionModifier: ViewModifier {
    @Binding var isPresented: Bool
    let blockName: String
    let completedCount: Int
    let totalCount: Int
    let streakDays: Int?

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                BlockCompletionModal(
                    blockName: blockName,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    streakDays: streakDays,
                    onContinue: {
                        withAnimation {
                            isPresented = false
                        }
                    }
                )
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func blockCompletion(
        isPresented: Binding<Bool>,
        blockName: String,
        completedCount: Int,
        totalCount: Int,
        streakDays: Int? = nil
    ) -> some View {
        modifier(BlockCompletionModifier(
            isPresented: isPresented,
            blockName: blockName,
            completedCount: completedCount,
            totalCount: totalCount,
            streakDays: streakDays
        ))
    }
}

#Preview {
    BlockCompletionModal(
        blockName: "Wake-Up",
        completedCount: 6,
        totalCount: 6,
        streakDays: 5,
        onContinue: {}
    )
}
