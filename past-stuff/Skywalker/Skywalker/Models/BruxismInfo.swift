//
//  BruxismInfo.swift
//  Skywalker
//
//  OpenJaw - Models for JSON-driven bruxism educational content
//

import Foundation
import SwiftUI

// MARK: - Top Level Data Structure

struct BruxismInfoData: Codable {
    let sections: [BruxismSection]
    let citations: [Citation]
    let disclaimer: String
}

// MARK: - Section

struct BruxismSection: Identifiable, Codable {
    let id: String
    let title: String
    let icon: String
    let color: String
    let content: [BruxismContent]

    var swiftUIColor: Color {
        switch color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "green": return .green
        case "indigo": return .indigo
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .gray
        }
    }
}

// MARK: - Content Types

enum BruxismContent: Codable {
    case paragraph(ParagraphContent)
    case bulletList(BulletListContent)
    case treatmentList(TreatmentListContent)
    case resourceList(ResourceListContent)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case items
        case citationIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "paragraph":
            let text = try container.decode(String.self, forKey: .text)
            let citationIds = try container.decodeIfPresent([String].self, forKey: .citationIds) ?? []
            self = .paragraph(ParagraphContent(text: text, citationIds: citationIds))

        case "bulletList":
            let items = try container.decode([String].self, forKey: .items)
            let citationIds = try container.decodeIfPresent([String].self, forKey: .citationIds) ?? []
            self = .bulletList(BulletListContent(items: items, citationIds: citationIds))

        case "treatmentList":
            let items = try container.decode([TreatmentItem].self, forKey: .items)
            let citationIds = try container.decodeIfPresent([String].self, forKey: .citationIds) ?? []
            self = .treatmentList(TreatmentListContent(items: items, citationIds: citationIds))

        case "resourceList":
            let items = try container.decode([ResourceItem].self, forKey: .items)
            let citationIds = try container.decodeIfPresent([String].self, forKey: .citationIds) ?? []
            self = .resourceList(ResourceListContent(items: items, citationIds: citationIds))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .paragraph(let content):
            try container.encode("paragraph", forKey: .type)
            try container.encode(content.text, forKey: .text)
            try container.encode(content.citationIds, forKey: .citationIds)

        case .bulletList(let content):
            try container.encode("bulletList", forKey: .type)
            try container.encode(content.items, forKey: .items)
            try container.encode(content.citationIds, forKey: .citationIds)

        case .treatmentList(let content):
            try container.encode("treatmentList", forKey: .type)
            try container.encode(content.items, forKey: .items)
            try container.encode(content.citationIds, forKey: .citationIds)

        case .resourceList(let content):
            try container.encode("resourceList", forKey: .type)
            try container.encode(content.items, forKey: .items)
            try container.encode(content.citationIds, forKey: .citationIds)
        }
    }
}

// MARK: - Content Structs

struct ParagraphContent: Codable {
    let text: String
    let citationIds: [String]
}

struct BulletListContent: Codable {
    let items: [String]
    let citationIds: [String]
}

struct TreatmentListContent: Codable {
    let items: [TreatmentItem]
    let citationIds: [String]
}

struct TreatmentItem: Codable {
    let name: String
    let description: String
    let citationIds: [String]
}

struct ResourceListContent: Codable {
    let items: [ResourceItem]
    let citationIds: [String]
}

struct ResourceItem: Codable {
    let title: String
    let subtitle: String
    let url: URL
    let isPrimary: Bool
}
