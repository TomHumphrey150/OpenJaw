//
//  MicroCelebration.swift
//  Skywalker
//
//  OpenJaw - Micro-celebration animation for item completion
//

import SwiftUI

struct MicroCelebrationView: View {
    @Binding var isPresented: Bool
    var message: String = "Nice!"

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var checkmarkScale: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 48, height: 48)

                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
            }
            .scaleEffect(scale)

            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .opacity(opacity)
        .onAppear {
            // Entrance animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1
                opacity = 1
            }

            // Checkmark pop
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.15)) {
                checkmarkScale = 1
            }

            // Trigger haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Auto dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                    scale = 0.8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - View Modifier

struct MicroCelebrationModifier: ViewModifier {
    @Binding var isPresented: Bool
    var message: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                Color.black.opacity(0.001) // Invisible overlay to block touches
                    .ignoresSafeArea()

                MicroCelebrationView(isPresented: $isPresented, message: message)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

extension View {
    func microCelebration(isPresented: Binding<Bool>, message: String = "Nice!") -> some View {
        modifier(MicroCelebrationModifier(isPresented: isPresented, message: message))
    }
}

#Preview {
    MicroCelebrationView(isPresented: .constant(true), message: "Nice work!")
}
