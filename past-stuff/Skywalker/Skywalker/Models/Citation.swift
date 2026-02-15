//
//  Citation.swift
//  Skywalker
//
//  OpenJaw - Academic citation model for evidence-based content
//

import Foundation

enum CitationType: String, Codable {
    case systematicReview
    case metaAnalysis
    case rct
    case cochrane
    case guideline
    case review

    var displayName: String {
        switch self {
        case .systematicReview: return "Systematic Review"
        case .metaAnalysis: return "Meta-Analysis"
        case .rct: return "RCT"
        case .cochrane: return "Cochrane Review"
        case .guideline: return "Guideline"
        case .review: return "Review"
        }
    }

    var iconName: String {
        switch self {
        case .cochrane: return "checkmark.seal.fill"
        case .systematicReview, .metaAnalysis: return "doc.text.magnifyingglass"
        case .rct: return "flask.fill"
        case .guideline: return "building.columns.fill"
        case .review: return "doc.text.fill"
        }
    }
}

struct Citation: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let source: String  // "Cochrane", "PMC", "NHS", etc.
    let year: Int
    let url: URL
    let type: CitationType

    static func == (lhs: Citation, rhs: Citation) -> Bool {
        lhs.id == rhs.id
    }
}
