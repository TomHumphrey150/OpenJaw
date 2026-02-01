//
//  SettingsView.swift
//  Skywalker
//
//  Bruxism Biofeedback - Settings screen for server and haptic configuration
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var watchService: WatchConnectivityService
    var eventLogger: EventLogger

    @Environment(\.dismiss) var dismiss
    @State private var discoveryService = ServerDiscoveryService()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Discover Servers")) {
                    if discoveryService.isScanning {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Scanning for servers...")
                                .foregroundColor(.secondary)
                        }

                        Button("Stop Scanning") {
                            discoveryService.stopScanning()
                        }

                        // Show checklist while scanning
                        scanningChecklist
                    } else {
                        Button(action: {
                            discoveryService.startScanning()
                        }) {
                            HStack {
                                Image(systemName: "wifi.circle.fill")
                                Text("Scan for Servers")
                            }
                        }
                    }

                    if let errorMessage = discoveryService.errorMessage {
                        Label {
                            Text(errorMessage)
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    if !discoveryService.discoveredServers.isEmpty {
                        ForEach(discoveryService.discoveredServers) { server in
                            Button(action: {
                                settings.serverIP = server.host
                                settings.serverPort = server.port
                                discoveryService.stopScanning()
                            }) {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                        .font(.headline)
                                    Text("\(server.host):\(server.port)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    } else if discoveryService.hasScannedOnce && !discoveryService.isScanning && discoveryService.errorMessage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)

                            Text("No Servers Found")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            troubleshootingChecklist
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                Section(header: Text("Server Connection")) {
                    HStack {
                        Text("IP Address")
                        Spacer()
                        TextField("192.168.1.43", text: $settings.serverIP)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("8765", value: $settings.serverPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if let url = settings.serverURL {
                        Text("WebSocket URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                Section(header: Text("Haptic Pattern")) {
                    Picker("Pattern", selection: $settings.hapticPattern) {
                        ForEach(HapticPattern.allCases) { pattern in
                            VStack(alignment: .leading) {
                                Text(pattern.displayName)
                                Text(pattern.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(pattern)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: settings.hapticPattern) { _, newValue in
                        watchService.updateHapticPattern(newValue)
                    }
                }

                Section(header: Text("Watch Connection")) {
                    HStack {
                        Text("Paired")
                        Spacer()
                        Image(systemName: watchService.isPaired ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(watchService.isPaired ? .green : .red)
                    }

                    HStack {
                        Text("App Installed")
                        Spacer()
                        Image(systemName: watchService.isWatchAppInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(watchService.isWatchAppInstalled ? .green : .red)
                    }

                    HStack {
                        Text("Reachable")
                        Spacer()
                        Image(systemName: watchService.watchReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(watchService.watchReachable ? .green : .red)
                    }
                }

                Section(header: Text("Tools")) {
                    Button(action: { watchService.sendTestHaptic() }) {
                        HStack {
                            Image(systemName: "hand.tap")
                            Text("Test Haptic")
                        }
                    }

                    NavigationLink(destination: EventHistoryView(eventLogger: eventLogger)) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("Event History")
                            Spacer()
                            Text("\(eventLogger.events.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button(action: {
                        settings.resetToDefaults()
                    }) {
                        HStack {
                            Spacer()
                            Text("Reset to Defaults")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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

    // MARK: - Checklist Views

    private var scanningChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("While scanning, make sure:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                checklistItem("Relay server is running on your Mac", icon: "terminal")
                checklistItem("iPhone and Mac are on the same WiFi network", icon: "wifi")
                checklistItem("VPN is disabled on both iPhone and Mac", icon: "network.slash")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private var troubleshootingChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            checklistItem("Run ./run.sh in relay-server folder", icon: "terminal")
            checklistItem("Both devices on same WiFi network", icon: "wifi")
            checklistItem("VPN disabled on iPhone and Mac", icon: "network.slash")
            checklistItem("Mac firewall allows connections", icon: "flame")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func checklistItem(_ text: String, icon: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
                .foregroundColor(.blue)
        }
    }
}
