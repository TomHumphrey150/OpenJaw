import Foundation
import Testing
@testable import Telocare

struct UserDataDocumentDecodingTests {
    @Test func decodesFullSchemaWithWrappedGraphData() throws {
        let data = try jsonData(from: wrappedGraphJSON)
        let decoded = try JSONDecoder().decode(UserDataDocument.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.dailyCheckIns["2026-02-21"] == ["PPI_TX"])
        #expect(decoded.interventionCompletionEvents.isEmpty)
        #expect(decoded.activeInterventions.isEmpty)
        #expect(decoded.appleHealthConnections == [:])
        #expect(decoded.customCausalDiagram?.graphData.nodes.count == 1)
    }

    @Test func decodesGraphFromDirectNodesAndEdgesFallback() throws {
        let data = try jsonData(from: directGraphJSON)
        let decoded = try JSONDecoder().decode(UserDataDocument.self, from: data)

        #expect(decoded.customCausalDiagram?.graphData.nodes.first?.data.id == "RMMA")
        #expect(decoded.customCausalDiagram?.graphData.edges.first?.data.source == "RMMA")
        #expect(decoded.activeInterventions.isEmpty)
    }

    @Test func decodesActiveInterventionsWhenPresent() throws {
        let data = try jsonData(from: activeInterventionsJSON)
        let decoded = try JSONDecoder().decode(UserDataDocument.self, from: data)

        #expect(decoded.activeInterventions == ["PPI_TX", "BED_ELEV_TX"])
    }

    @Test func decodesInterventionCompletionEventsWhenPresent() throws {
        let data = try jsonData(from: completionEventsJSON)
        let decoded = try JSONDecoder().decode(UserDataDocument.self, from: data)

        #expect(decoded.interventionCompletionEvents.count == 2)
        #expect(decoded.interventionCompletionEvents.first?.interventionId == "PPI_TX")
        #expect(decoded.interventionCompletionEvents.first?.source == .binaryCheck)
        #expect(decoded.interventionCompletionEvents.last?.source == .doseIncrement)
    }

    @Test func failsToDecodeInvalidGraphPayload() throws {
        #expect(throws: DecodingError.self) {
            let data = try jsonData(from: invalidGraphJSON)
            _ = try JSONDecoder().decode(UserDataDocument.self, from: data)
        }
    }

    private func jsonData(from value: String) throws -> Data {
        guard let data = value.data(using: .utf8) else {
            throw TestFailure.invalidJSONData
        }

        return data
    }
}

private enum TestFailure: Error {
    case invalidJSONData
}

private let wrappedGraphJSON = """
{
  "version": 1,
  "personalStudies": [],
  "notes": [],
  "experiments": [],
  "interventionRatings": [],
  "dailyCheckIns": {"2026-02-21": ["PPI_TX"]},
  "nightExposures": [],
  "nightOutcomes": [],
  "morningStates": [],
  "habitTrials": [],
  "habitClassifications": [],
  "hiddenInterventions": [],
  "unlockedAchievements": [],
  "experienceFlow": {
    "hasCompletedInitialGuidedFlow": false,
    "lastGuidedEntryDate": null,
    "lastGuidedCompletedDate": null,
    "lastGuidedStatus": "not_started"
  },
  "customCausalDiagram": {
    "graphData": {
      "nodes": [
        {"data": {"id": "RMMA", "label": "RMMA", "styleClass": "robust", "tier": 7}}
      ],
      "edges": []
    },
    "lastModified": "2026-02-21T00:00:00.000Z"
  }
}
"""

private let directGraphJSON = """
{
  "version": 1,
  "personalStudies": [],
  "notes": [],
  "experiments": [],
  "interventionRatings": [],
  "dailyCheckIns": {},
  "nightExposures": [],
  "nightOutcomes": [],
  "morningStates": [],
  "habitTrials": [],
  "habitClassifications": [],
  "hiddenInterventions": [],
  "unlockedAchievements": [],
  "experienceFlow": {
    "hasCompletedInitialGuidedFlow": false,
    "lastGuidedEntryDate": null,
    "lastGuidedCompletedDate": null,
    "lastGuidedStatus": "not_started"
  },
  "customCausalDiagram": {
    "nodes": [
      {"data": {"id": "RMMA", "label": "RMMA", "styleClass": "robust", "tier": 7}}
    ],
    "edges": [
      {"data": {"source": "RMMA", "target": "NECK_TIGHTNESS", "edgeType": "dashed"}}
    ],
    "lastModified": "2026-02-21T00:00:00.000Z"
  }
}
"""

private let invalidGraphJSON = """
{
  "version": 1,
  "personalStudies": [],
  "notes": [],
  "experiments": [],
  "interventionRatings": [],
  "dailyCheckIns": {},
  "nightExposures": [],
  "nightOutcomes": [],
  "morningStates": [],
  "habitTrials": [],
  "habitClassifications": [],
  "hiddenInterventions": [],
  "unlockedAchievements": [],
  "experienceFlow": {
    "hasCompletedInitialGuidedFlow": false,
    "lastGuidedEntryDate": null,
    "lastGuidedCompletedDate": null,
    "lastGuidedStatus": "not_started"
  },
  "customCausalDiagram": {
    "lastModified": "2026-02-21T00:00:00.000Z"
  }
}
"""

private let activeInterventionsJSON = """
{
  "version": 1,
  "personalStudies": [],
  "notes": [],
  "experiments": [],
  "interventionRatings": [],
  "dailyCheckIns": {},
  "nightExposures": [],
  "nightOutcomes": [],
  "morningStates": [],
  "habitTrials": [],
  "habitClassifications": [],
  "activeInterventions": ["PPI_TX", "BED_ELEV_TX"],
  "hiddenInterventions": [],
  "unlockedAchievements": [],
  "experienceFlow": {
    "hasCompletedInitialGuidedFlow": false,
    "lastGuidedEntryDate": null,
    "lastGuidedCompletedDate": null,
    "lastGuidedStatus": "not_started"
  },
  "customCausalDiagram": {
    "graphData": {
      "nodes": [],
      "edges": []
    },
    "lastModified": "2026-02-21T00:00:00.000Z"
  }
}
"""

private let completionEventsJSON = """
{
  "version": 1,
  "personalStudies": [],
  "notes": [],
  "experiments": [],
  "interventionRatings": [],
  "dailyCheckIns": {},
  "interventionCompletionEvents": [
    {
      "interventionId": "PPI_TX",
      "occurredAt": "2026-02-21T08:00:00Z",
      "source": "binaryCheck"
    },
    {
      "interventionId": "WATER_INTAKE",
      "occurredAt": "2026-02-21T08:05:00Z",
      "source": "doseIncrement"
    }
  ],
  "nightExposures": [],
  "nightOutcomes": [],
  "morningStates": [],
  "habitTrials": [],
  "habitClassifications": [],
  "hiddenInterventions": [],
  "unlockedAchievements": [],
  "experienceFlow": {
    "hasCompletedInitialGuidedFlow": false,
    "lastGuidedEntryDate": null,
    "lastGuidedCompletedDate": null,
    "lastGuidedStatus": "not_started"
  },
  "customCausalDiagram": {
    "graphData": {
      "nodes": [],
      "edges": []
    },
    "lastModified": "2026-02-21T00:00:00.000Z"
  }
}
"""
