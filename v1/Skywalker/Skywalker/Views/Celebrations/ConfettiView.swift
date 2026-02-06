//
//  ConfettiView.swift
//  Skywalker
//
//  OpenJaw - Celebratory confetti particle animation
//

import SwiftUI

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animationTimer: Timer?

    let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .yellow]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                        .rotationEffect(.degrees(particle.rotation))
                }
            }
            .onAppear {
                startAnimation(in: geometry.size)
            }
            .onDisappear {
                stopAnimation()
            }
        }
        .allowsHitTesting(false)
    }

    private func startAnimation(in size: CGSize) {
        // Create initial burst of particles
        for _ in 0..<50 {
            let particle = createParticle(in: size)
            particles.append(particle)
        }

        // Animate particles
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            updateParticles(in: size)
        }

        // Stop after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            stopAnimation()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        withAnimation(.easeOut(duration: 0.5)) {
            particles.removeAll()
        }
    }

    private func createParticle(in size: CGSize) -> ConfettiParticle {
        ConfettiParticle(
            position: CGPoint(x: size.width / 2, y: -20),
            velocity: CGPoint(
                x: CGFloat.random(in: -150...150),
                y: CGFloat.random(in: 200...400)
            ),
            color: colors.randomElement() ?? .blue,
            size: CGFloat.random(in: 6...12),
            rotation: Double.random(in: 0...360),
            rotationSpeed: Double.random(in: -360...360),
            opacity: 1.0
        )
    }

    private func updateParticles(in size: CGSize) {
        particles = particles.compactMap { particle in
            var updated = particle

            // Update position
            updated.position.x += particle.velocity.x * 0.016
            updated.position.y += particle.velocity.y * 0.016

            // Apply gravity
            updated.velocity.y += 200 * 0.016

            // Apply air resistance
            updated.velocity.x *= 0.99
            updated.velocity.y *= 0.99

            // Update rotation
            updated.rotation += particle.rotationSpeed * 0.016

            // Fade out as it falls
            if updated.position.y > size.height * 0.7 {
                updated.opacity -= 0.02
            }

            // Remove if off screen or faded out
            if updated.position.y > size.height + 50 || updated.opacity <= 0 {
                return nil
            }

            return updated
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var color: Color
    var size: CGFloat
    var rotation: Double
    var rotationSpeed: Double
    var opacity: Double
}

// MARK: - Confetti Modifier

struct ConfettiModifier: ViewModifier {
    @Binding var isActive: Bool

    func body(content: Content) -> some View {
        ZStack {
            content

            if isActive {
                ConfettiView()
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    func confetti(isActive: Binding<Bool>) -> some View {
        modifier(ConfettiModifier(isActive: isActive))
    }
}

#Preview {
    ZStack {
        Color(.systemBackground)
        ConfettiView()
    }
}
