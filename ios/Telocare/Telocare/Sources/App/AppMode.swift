import Foundation

enum AppMode: String, Equatable {
    case guided
    case explore
}

enum GuidedStep: Int, CaseIterable, Equatable {
    case outcomes
    case situation
    case inputs

    var position: Int {
        rawValue + 1
    }

    var title: String {
        switch self {
        case .outcomes:
            return "Outcomes"
        case .situation:
            return "Situation"
        case .inputs:
            return "Inputs"
        }
    }

    var subtitle: String {
        switch self {
        case .outcomes:
            return "Start with measurable changes from the last check-in."
        case .situation:
            return "Review the graph to understand why outcomes changed."
        case .inputs:
            return "Confirm what actions to take next."
        }
    }

    var announcement: String {
        switch self {
        case .outcomes:
            return "Moved to Outcomes step."
        case .situation:
            return "Moved to Situation step."
        case .inputs:
            return "Moved to Inputs step."
        }
    }
}

enum ExploreTab: String, CaseIterable, Identifiable, Equatable {
    case outcomes
    case situation
    case inputs
    case chat

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .outcomes:
            return "Outcomes"
        case .situation:
            return "Situation"
        case .inputs:
            return "Inputs"
        case .chat:
            return "Chat"
        }
    }

    var symbolName: String {
        switch self {
        case .outcomes:
            return "chart.line.uptrend.xyaxis"
        case .situation:
            return "point.3.connected.trianglepath.dotted"
        case .inputs:
            return "checklist"
        case .chat:
            return "message"
        }
    }
}

enum ExploreContextAction: String, CaseIterable, Identifiable, Equatable {
    case improveInput
    case explainLinks
    case refineNode
    case interpretOutcome

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .improveInput:
            return "Improve Input"
        case .explainLinks:
            return "Explain Links"
        case .refineNode:
            return "Refine Node"
        case .interpretOutcome:
            return "Interpret Outcome"
        }
    }

    var detail: String {
        switch self {
        case .improveInput:
            return "AI will suggest a typed input patch with evidence requirements."
        case .explainLinks:
            return "AI will summarize mechanism links with source confidence."
        case .refineNode:
            return "AI will propose a bounded node update for review."
        case .interpretOutcome:
            return "AI will draft a global narrative patch for outcome interpretation."
        }
    }

    var announcement: String {
        switch self {
        case .improveInput:
            return "Requested AI input improvement."
        case .explainLinks:
            return "Requested AI link explanation."
        case .refineNode:
            return "Requested AI node refinement."
        case .interpretOutcome:
            return "Requested AI outcome interpretation."
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .improveInput:
            return AccessibilityID.exploreActionImproveInput
        case .explainLinks:
            return AccessibilityID.exploreActionExplainLinks
        case .refineNode:
            return AccessibilityID.exploreActionRefineNode
        case .interpretOutcome:
            return AccessibilityID.exploreActionInterpretOutcome
        }
    }
}
