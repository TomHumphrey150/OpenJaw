import Foundation
import Testing
@testable import Telocare

struct GraphBridgeModelsTests {
    @Test func setDisplayFlagsCommandEncodesInterventionToggle() throws {
        let flags = GraphDisplayFlags(
            showFeedbackEdges: true,
            showProtectiveEdges: false,
            showInterventionNodes: true
        )

        let json = try #require(GraphCommand.setDisplayFlags(flags).jsonString())
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(DisplayFlagsEnvelope.self, from: data)

        #expect(decoded.command == "setDisplayFlags")
        #expect(decoded.payload.showFeedbackEdges == true)
        #expect(decoded.payload.showProtectiveEdges == false)
        #expect(decoded.payload.showInterventionNodes == true)
    }

    @Test func setSkinCommandEncodesGraphSkinPayload() throws {
        let graphSkin = GraphSkin(
            backgroundColor: "#FAF5EE",
            textColor: "#403B38",
            nodeBackgroundColor: "#FFFDF7",
            nodeBorderDefaultColor: "#BFB8B3",
            nodeBorderRobustColor: "#85C28F",
            nodeBorderModerateColor: "#FF9966",
            nodeBorderPreliminaryColor: "#D4A5FF",
            nodeBorderMechanismColor: "#7DD3FC",
            nodeBorderSymptomColor: "#FF7060",
            nodeBorderInterventionColor: "#FF7060",
            edgeTextBackgroundColor: "#FAF5EE",
            tooltipBackgroundColor: "rgba(255, 253, 247, 0.97)",
            tooltipBorderColor: "rgba(140, 133, 128, 0.4)",
            selectionOverlayColor: "#FF7060",
            edgeCausalColor: "#B45309",
            edgeProtectiveColor: "#1B4332",
            edgeFeedbackColor: "#FF9966",
            edgeMechanismColor: "#1E3A5F",
            edgeInterventionColor: "#065F46"
        )

        let json = try #require(GraphCommand.setSkin(graphSkin).jsonString())
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(GraphSkinEnvelope.self, from: data)

        #expect(decoded.command == "setSkin")
        #expect(decoded.payload == graphSkin)
    }
}

private struct DisplayFlagsEnvelope: Decodable {
    let command: String
    let payload: GraphDisplayFlags
}

private struct GraphSkinEnvelope: Decodable {
    let command: String
    let payload: GraphSkin
}
