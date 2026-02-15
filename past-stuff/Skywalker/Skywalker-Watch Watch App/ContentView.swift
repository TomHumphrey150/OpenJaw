//
//  ContentView.swift
//  Skywalker-Watch Watch App
//
//  Bruxism Biofeedback - Watch status display
//

import SwiftUI

struct ContentView: View {
    @State var connectivityManager: WatchConnectivityManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Connection Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectivityManager.isConnectedToPhone ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(connectivityManager.isConnectedToPhone ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Event Counter - LARGE
                VStack(spacing: 4) {
                    Text("Events")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(connectivityManager.totalEvents)")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }

                Divider()

                // Last Pattern
                VStack(spacing: 4) {
                    Text("Last Pattern")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(connectivityManager.lastPattern.displayName)
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                // Last Haptic Time
                if let lastTime = connectivityManager.lastHapticTime {
                    VStack(spacing: 4) {
                        Text("Last Event")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(lastTime, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No events yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Debug: Last Message
                VStack(spacing: 4) {
                    Text("Last Message")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(connectivityManager.lastMessageReceived)
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                        .lineLimit(3)
                }

                Divider()

                // Local Test Button
                Button(action: {
                    connectivityManager.testHaptic()
                }) {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                        Text("Test Haptic Locally")
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        // .brightness(-0.3) // Uncomment for sleep mode dimming
    }
}

#Preview {
    ContentView(connectivityManager: WatchConnectivityManager())
}
