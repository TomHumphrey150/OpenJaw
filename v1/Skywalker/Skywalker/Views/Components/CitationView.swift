//
//  CitationView.swift
//  Skywalker
//
//  OpenJaw - Compact citation display with tap-to-open functionality
//

import SwiftUI

// MARK: - Inline Citation Badge

/// Small inline badge shown after text with citations, e.g. "affects 8-31% [Cochrane]"
struct CitationBadge: View {
    let citation: Citation

    var body: some View {
        Link(destination: citation.url) {
            HStack(spacing: 2) {
                Image(systemName: citation.type.iconName)
                    .font(.caption2)
                Text(citation.source)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(4)
        }
    }
}

// MARK: - Citation Row

/// Full citation row for sources section at bottom of cards
struct CitationRow: View {
    let citation: Citation

    var body: some View {
        Link(destination: citation.url) {
            HStack(spacing: 8) {
                Image(systemName: citation.type.iconName)
                    .foregroundColor(typeColor)
                    .font(.body)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text(citation.source)
                            .font(.caption2)
                        Text("•")
                        Text(String(citation.year))
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
        }
    }

    private var typeColor: Color {
        switch citation.type {
        case .cochrane: return .green
        case .systematicReview, .metaAnalysis: return .blue
        case .rct: return .orange
        case .guideline: return .purple
        case .review: return .gray
        }
    }
}

// MARK: - Citation List

/// Shows multiple citations in a compact list
struct CitationList: View {
    let citations: [Citation]
    let title: String

    init(citations: [Citation], title: String = "Sources") {
        self.citations = citations
        self.title = title
    }

    var body: some View {
        if !citations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(citations) { citation in
                    CitationRow(citation: citation)
                }
            }
        }
    }
}

// MARK: - Inline Badges View

/// Helper to render inline citation badges at end of text
struct InlineCitationBadges: View {
    let citations: [Citation]

    var body: some View {
        if !citations.isEmpty {
            HStack(spacing: 4) {
                ForEach(citations) { citation in
                    CitationBadge(citation: citation)
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        // Inline badge preview
        HStack {
            Text("Affects 8-31% of population")
                .font(.subheadline)
            CitationBadge(citation: Citation(
                id: "test",
                title: "Test Citation",
                source: "Cochrane",
                year: 2023,
                url: URL(string: "https://example.com")!,
                type: .cochrane
            ))
        }

        Divider()

        // Full row preview
        CitationRow(citation: Citation(
            id: "test2",
            title: "Biofeedback for sleep bruxism: A systematic review",
            source: "PMC",
            year: 2023,
            url: URL(string: "https://example.com")!,
            type: .systematicReview
        ))
    }
    .padding()
}
