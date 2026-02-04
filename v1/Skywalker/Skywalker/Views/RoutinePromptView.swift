//
//  RoutinePromptView.swift
//  Skywalker
//
//  OpenJaw - Modal for wake-up/wind-down routine prompts
//

import SwiftUI

struct RoutinePromptView: View {
    let promptType: RoutineService.RoutinePromptType
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    let onLateStartOption: ((RoutineService.LateStartOption) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                iconSection

                // Title and subtitle
                titleSection

                Spacer()

                // Actions
                actionButtons
            }
            .padding(24)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var iconSection: some View {
        switch promptType {
        case .wakeUp:
            Image(systemName: "sunrise.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .windDown:
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .lateStartCatchUp:
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var titleSection: some View {
        switch promptType {
        case .wakeUp:
            VStack(spacing: 12) {
                Text("Good morning!")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Ready to start your morning routine?")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .windDown:
            VStack(spacing: 12) {
                Text("Time to wind down")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Ready to start your pre-bed routine?")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .lateStartCatchUp(let minutes):
            VStack(spacing: 12) {
                Text("Late start today?")
                    .font(.title)
                    .fontWeight(.bold)
                Text("You have \(formatMinutes(minutes)) until afternoon. How would you like to proceed?")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch promptType {
        case .wakeUp:
            VStack(spacing: 12) {
                Button(action: {
                    onConfirm()
                    dismiss()
                }) {
                    Text("Begin")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }

                Button(action: {
                    onDismiss()
                    dismiss()
                }) {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

        case .windDown:
            VStack(spacing: 12) {
                Button(action: {
                    onConfirm()
                    dismiss()
                }) {
                    Text("Begin")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }

                Button(action: {
                    onDismiss()
                    dismiss()
                }) {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

        case .lateStartCatchUp:
            VStack(spacing: 12) {
                Button(action: {
                    onLateStartOption?(.fullMorning)
                    dismiss()
                }) {
                    VStack(spacing: 4) {
                        Text("Full morning routine")
                            .font(.headline)
                        Text("Push afternoon back")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
                }

                Button(action: {
                    onLateStartOption?(.compressedMorning)
                    dismiss()
                }) {
                    VStack(spacing: 4) {
                        Text("Compressed morning")
                            .font(.headline)
                        Text("Essential items only")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .cornerRadius(12)
                }

                Button(action: {
                    onLateStartOption?(.skipMorning)
                    dismiss()
                }) {
                    Text("Skip to afternoon")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(mins)m"
            }
        } else {
            return "\(minutes) minutes"
        }
    }
}

#Preview("Wake Up") {
    RoutinePromptView(
        promptType: .wakeUp,
        onConfirm: {},
        onDismiss: {},
        onLateStartOption: nil
    )
}

#Preview("Wind Down") {
    RoutinePromptView(
        promptType: .windDown,
        onConfirm: {},
        onDismiss: {},
        onLateStartOption: nil
    )
}

#Preview("Late Start") {
    RoutinePromptView(
        promptType: .lateStartCatchUp(minutesUntilAfternoon: 45),
        onConfirm: {},
        onDismiss: {},
        onLateStartOption: { _ in }
    )
}
