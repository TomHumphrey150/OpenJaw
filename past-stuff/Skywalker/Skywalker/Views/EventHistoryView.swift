//
//  EventHistoryView.swift
//  Skywalker
//
//  Bruxism Biofeedback - Event history timeline
//

import SwiftUI

struct EventHistoryView: View {
    var eventLogger: EventLogger
    @Environment(\.dismiss) var dismiss

    @State private var showingExportSheet = false
    @State private var exportedCSV = ""

    var body: some View {
        NavigationView {
            Group {
                if eventLogger.events.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Events Yet")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        Text("Jaw clench events will appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        Section(header: Text("All Events (\(eventLogger.events.count))")) {
                            ForEach(eventLogger.events.reversed()) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Event History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: exportEvents) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive, action: clearAllEvents) {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                ShareSheet(activityItems: [exportedCSV])
            }
        }
    }

    private func exportEvents() {
        exportedCSV = eventLogger.exportEvents()
        showingExportSheet = true
    }

    private func clearAllEvents() {
        eventLogger.clearEvents()
    }
}

struct EventRow: View {
    let event: JawClenchEvent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.formattedTime)
                    .font(.body)
                    .fontWeight(.medium)

                Text(event.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("#\(event.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

// Share sheet for exporting CSV
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
