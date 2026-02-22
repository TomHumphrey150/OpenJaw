import Foundation

struct GraphDisplayFlags: Codable, Equatable {
    let showFeedbackEdges: Bool
    let showProtectiveEdges: Bool
    let showInterventionNodes: Bool
}

struct GraphSkin: Codable, Equatable {
    let backgroundColor: String
    let textColor: String
    let nodeBackgroundColor: String
    let nodeBorderDefaultColor: String
    let nodeBorderRobustColor: String
    let nodeBorderModerateColor: String
    let nodeBorderPreliminaryColor: String
    let nodeBorderMechanismColor: String
    let nodeBorderSymptomColor: String
    let nodeBorderInterventionColor: String
    let edgeTextBackgroundColor: String
    let tooltipBackgroundColor: String
    let tooltipBorderColor: String
    let selectionOverlayColor: String
    let edgeCausalColor: String
    let edgeProtectiveColor: String
    let edgeFeedbackColor: String
    let edgeMechanismColor: String
    let edgeInterventionColor: String
}

enum GraphEvent: Equatable {
    case graphReady
    case nodeSelected(id: String, label: String)
    case edgeSelected(
        sourceID: String,
        targetID: String,
        sourceLabel: String,
        targetLabel: String,
        label: String?,
        edgeType: String?
    )
    case viewportChanged(zoom: Double)
    case renderError(message: String)
}

enum GraphCommand {
    case setGraphData(CausalGraphData)
    case setDisplayFlags(GraphDisplayFlags)
    case setSkin(GraphSkin)
    case focusNode(String)

    var name: String {
        switch self {
        case .setGraphData:
            return "setGraphData"
        case .setDisplayFlags:
            return "setDisplayFlags"
        case .setSkin:
            return "setSkin"
        case .focusNode:
            return "focusNode"
        }
    }

    func jsonString(encoder: JSONEncoder = JSONEncoder()) -> String? {
        switch self {
        case .setGraphData(let graphData):
            return encode(
                envelope: GraphCommandEnvelope(command: name, payload: graphData),
                encoder: encoder
            )
        case .setDisplayFlags(let flags):
            return encode(
                envelope: GraphCommandEnvelope(command: name, payload: flags),
                encoder: encoder
            )
        case .setSkin(let skin):
            return encode(
                envelope: GraphCommandEnvelope(command: name, payload: skin),
                encoder: encoder
            )
        case .focusNode(let nodeID):
            return encode(
                envelope: GraphCommandEnvelope(command: name, payload: FocusNodePayload(nodeID: nodeID)),
                encoder: encoder
            )
        }
    }

    private func encode<Payload: Encodable>(envelope: GraphCommandEnvelope<Payload>, encoder: JSONEncoder) -> String? {
        guard let data = try? encoder.encode(envelope) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

private struct GraphCommandEnvelope<Payload: Encodable>: Encodable {
    let command: String
    let payload: Payload
}

private struct FocusNodePayload: Encodable {
    let nodeID: String
}
