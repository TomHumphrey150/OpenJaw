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
}

private struct DisplayFlagsEnvelope: Decodable {
    let command: String
    let payload: GraphDisplayFlags
}
