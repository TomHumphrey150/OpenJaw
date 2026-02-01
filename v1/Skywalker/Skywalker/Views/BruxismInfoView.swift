//
//  BruxismInfoView.swift
//  Skywalker
//
//  OpenJaw - Educational content about bruxism with authoritative sources
//

import SwiftUI

struct BruxismInfoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.catalogDataService) var catalogDataService

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Understanding Bruxism")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Teeth grinding and jaw clenching during sleep")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)

                    // NHS Resource Banner (Primary)
                    if let nhsCitation = catalogDataService.citation(byId: "nhs_bruxism") {
                        Link(destination: nhsCitation.url) {
                            HStack {
                                Image(systemName: "building.columns.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("NHS - Official Guidance")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text("Trusted medical information from the UK National Health Service")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }

                    // Dynamic sections from JSON
                    if let bruxismInfo = catalogDataService.bruxismInfo {
                        ForEach(bruxismInfo.sections) { section in
                            InfoSection(
                                section: section,
                                citations: catalogDataService.citations(forIds: collectCitationIds(from: section))
                            )
                        }

                        // Disclaimer
                        Text(bruxismInfo.disclaimer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        // Fallback if JSON not loaded
                        Text("Content not available")
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
            .navigationTitle("About Bruxism")
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

    private func collectCitationIds(from section: BruxismSection) -> [String] {
        var ids: [String] = []
        for content in section.content {
            switch content {
            case .paragraph(let p):
                ids.append(contentsOf: p.citationIds)
            case .bulletList(let b):
                ids.append(contentsOf: b.citationIds)
            case .treatmentList(let t):
                ids.append(contentsOf: t.citationIds)
                for item in t.items {
                    ids.append(contentsOf: item.citationIds)
                }
            case .resourceList(let r):
                ids.append(contentsOf: r.citationIds)
            }
        }
        return Array(Set(ids)) // Deduplicate
    }
}

// MARK: - Supporting Views

private struct InfoSection: View {
    let section: BruxismSection
    let citations: [Citation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: section.icon)
                    .foregroundColor(section.swiftUIColor)
                    .font(.title2)
                Text(section.title)
                    .font(.headline)
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(section.content.enumerated()), id: \.offset) { _, content in
                    ContentRenderer(content: content, citations: citations)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            // Sources at bottom of card
            if !citations.isEmpty && section.id != "resources" {
                Divider()
                    .padding(.top, 4)
                CitationList(citations: citations)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(section.swiftUIColor.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct ContentRenderer: View {
    let content: BruxismContent
    let citations: [Citation]

    @Environment(\.catalogDataService) var catalogDataService

    var body: some View {
        switch content {
        case .paragraph(let p):
            VStack(alignment: .leading, spacing: 4) {
                Text(p.text)
                    .multilineTextAlignment(.leading)
                if !p.citationIds.isEmpty {
                    InlineCitationBadges(citations: catalogDataService.citations(forIds: p.citationIds))
                }
            }

        case .bulletList(let b):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(b.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(item)
                    }
                }
                if !b.citationIds.isEmpty {
                    InlineCitationBadges(citations: catalogDataService.citations(forIds: b.citationIds))
                        .padding(.top, 4)
                }
            }

        case .treatmentList(let t):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(t.items, id: \.name) { item in
                    TreatmentRow(item: item)
                }
            }

        case .resourceList(let r):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(r.items, id: \.url) { item in
                    ResourceLink(item: item)
                }
            }
        }
    }
}

private struct TreatmentRow: View {
    let item: TreatmentItem

    @Environment(\.catalogDataService) var catalogDataService

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                Text(item.name)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                if !item.citationIds.isEmpty {
                    InlineCitationBadges(citations: catalogDataService.citations(forIds: item.citationIds))
                }
            }
            Text(item.description)
        }
    }
}

private struct ResourceLink: View {
    let item: ResourceItem

    var body: some View {
        Link(destination: item.url) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if item.isPrimary {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        Text(item.title)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    BruxismInfoView()
}
