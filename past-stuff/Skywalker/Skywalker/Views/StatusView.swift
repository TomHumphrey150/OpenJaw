//
//  StatusView.swift
//  Skywalker
//
//  Bruxism Biofeedback - Connection status display component
//

import SwiftUI

struct StatusView: View {
    var webSocketService: WebSocketService
    var watchService: WatchConnectivityService

    var body: some View {
        HStack(spacing: 24) {
            // Server status
            HStack(spacing: 6) {
                Circle()
                    .fill(webSocketService.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("Server")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Watch status
            HStack(spacing: 6) {
                Circle()
                    .fill(watchService.watchStatusColor)
                    .frame(width: 8, height: 8)
                Text("Watch")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
