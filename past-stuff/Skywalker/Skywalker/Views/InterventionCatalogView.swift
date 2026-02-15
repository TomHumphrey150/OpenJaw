//
//  InterventionCatalogView.swift
//  Skywalker
//
//  OpenJaw - Browse and select interventions from catalog
//

import SwiftUI

struct InterventionCatalogView: View {
    var interventionService: InterventionService
    @Environment(\.dismiss) var dismiss
    @Environment(\.catalogDataService) var catalogDataService
    @State private var selectedDefinition: InterventionDefinition?

    var body: some View {
        NavigationView {
            List {
                ForEach(InterventionTier.allCases, id: \.self) { tier in
                    Section {
                        ForEach(catalogDataService.byTier(tier)) { definition in
                            InterventionCatalogRow(
                                definition: definition,
                                isSelected: interventionService.hasIntervention(definition.id),
                                onToggle: {
                                    interventionService.toggleIntervention(definition.id)
                                },
                                onShowInfo: {
                                    selectedDefinition = definition
                                }
                            )
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tier.displayName)
                                .font(.headline)
                            Text(tier.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontWeight(.regular)
                        }
                        .textCase(nil)
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Interventions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedDefinition) { definition in
                InterventionDetailView(definition: definition, interventionService: interventionService)
            }
        }
    }
}

// MARK: - Catalog Row

private struct InterventionCatalogRow: View {
    let definition: InterventionDefinition
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowInfo: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Icon (using emoji from definition)
                Text(definition.emoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(tierColor.opacity(0.15))
                    .cornerRadius(8)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(definition.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    // Tags - simplified to prevent wrapping
                    HStack(spacing: 6) {
                        Text(definition.frequency.displayName)
                            .foregroundColor(.secondary)
                        if let roi = definition.roiTier {
                            Text("ROI: \(roi)")
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(roiColor(roi).opacity(0.2))
                                .foregroundColor(roiColor(roi))
                                .cornerRadius(2)
                        }
                    }
                    .font(.caption2)
                }

                Spacer()

                // Info button
                Button(action: onShowInfo) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .green : .secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var tierColor: Color {
        switch definition.tier {
        case .strong: return .blue
        case .moderate: return .orange
        case .lower: return .purple
        }
    }

    private func roiColor(_ tier: String) -> Color {
        switch tier {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        case "D": return .red
        default: return .gray
        }
    }
}

#Preview {
    InterventionCatalogView(interventionService: InterventionService())
}
