//
//  CatalogDataServiceTests.swift
//  SkywalkerTests
//
//  Tests for JSON-driven intervention catalog and bruxism info
//

import Testing
import Foundation
@testable import Skywalker

struct CatalogDataServiceTests {

    // MARK: - Intervention JSON Parsing Tests

    @Test func testInterventionDefinitionDecoding() async throws {
        let json = """
        {
            "id": "test_intervention",
            "name": "Test Intervention",
            "emoji": "🧪",
            "icon": "testtube.2",
            "description": "A test intervention",
            "detailedDescription": "Detailed description here",
            "tier": 1,
            "frequency": "daily",
            "trackingType": "binary",
            "isRemindable": true,
            "defaultReminderMinutes": 60,
            "externalLink": "https://example.com",
            "evidenceLevel": "Moderate",
            "evidenceSummary": "Test evidence summary",
            "citationIds": ["test_citation"],
            "roiTier": "A",
            "easeScore": 8,
            "costRange": "$0-50"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let definition = try decoder.decode(InterventionDefinition.self, from: data)

        #expect(definition.id == "test_intervention")
        #expect(definition.name == "Test Intervention")
        #expect(definition.emoji == "🧪")
        #expect(definition.tier == .strong)
        #expect(definition.frequency == .daily)
        #expect(definition.trackingType == .binary)
        #expect(definition.isRemindable == true)
        #expect(definition.defaultReminderMinutes == 60)
        #expect(definition.evidenceLevel == "Moderate")
        #expect(definition.roiTier == "A")
        #expect(definition.easeScore == 8)
        #expect(definition.costRange == "$0-50")
        #expect(definition.citationIds.count == 1)
    }

    @Test func testInterventionDefinitionMinimalDecoding() async throws {
        // Test with minimal required fields only
        let json = """
        {
            "id": "minimal",
            "name": "Minimal",
            "icon": "star",
            "description": "Minimal description",
            "tier": 2,
            "frequency": "hourly",
            "trackingType": "counter",
            "isRemindable": false
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let definition = try decoder.decode(InterventionDefinition.self, from: data)

        #expect(definition.id == "minimal")
        #expect(definition.emoji == "✨") // Default
        #expect(definition.tier == .moderate)
        #expect(definition.frequency == .hourly)
        #expect(definition.trackingType == .counter)
        #expect(definition.evidenceLevel == nil)
        #expect(definition.citationIds.isEmpty)
    }

    @Test func testAllTiersDecodeCorrectly() async throws {
        let tiers = [
            (1, InterventionTier.strong),
            (2, InterventionTier.moderate),
            (3, InterventionTier.lower)
        ]

        for (tierInt, expectedTier) in tiers {
            let json = """
            {
                "id": "tier_test",
                "name": "Tier Test",
                "icon": "star",
                "description": "Test",
                "tier": \(tierInt),
                "frequency": "daily",
                "trackingType": "binary",
                "isRemindable": false
            }
            """

            let data = json.data(using: .utf8)!
            let definition = try JSONDecoder().decode(InterventionDefinition.self, from: data)
            #expect(definition.tier == expectedTier)
        }
    }

    @Test func testAllFrequenciesDecodeCorrectly() async throws {
        let frequencies = ["continuous", "hourly", "daily", "weekly", "quarterly", "asNeeded"]

        for freq in frequencies {
            let json = """
            {
                "id": "freq_test",
                "name": "Freq Test",
                "icon": "star",
                "description": "Test",
                "tier": 1,
                "frequency": "\(freq)",
                "trackingType": "binary",
                "isRemindable": false
            }
            """

            let data = json.data(using: .utf8)!
            let definition = try JSONDecoder().decode(InterventionDefinition.self, from: data)
            #expect(definition.frequency.rawValue == freq)
        }
    }

    @Test func testAllTrackingTypesDecodeCorrectly() async throws {
        let types = ["binary", "counter", "timer", "checklist", "appointment", "automatic"]

        for trackingType in types {
            let json = """
            {
                "id": "type_test",
                "name": "Type Test",
                "icon": "star",
                "description": "Test",
                "tier": 1,
                "frequency": "daily",
                "trackingType": "\(trackingType)",
                "isRemindable": false
            }
            """

            let data = json.data(using: .utf8)!
            let definition = try JSONDecoder().decode(InterventionDefinition.self, from: data)
            #expect(definition.trackingType.rawValue == trackingType)
        }
    }

    // MARK: - Citation Tests

    @Test func testCitationDecoding() async throws {
        let json = """
        {
            "id": "test_citation",
            "title": "Test Research Paper",
            "source": "PMC",
            "year": 2023,
            "url": "https://example.com/paper",
            "type": "systematicReview"
        }
        """

        let data = json.data(using: .utf8)!
        let citation = try JSONDecoder().decode(Citation.self, from: data)

        #expect(citation.id == "test_citation")
        #expect(citation.title == "Test Research Paper")
        #expect(citation.source == "PMC")
        #expect(citation.year == 2023)
        #expect(citation.type == .systematicReview)
    }

    @Test func testAllCitationTypesDecodeCorrectly() async throws {
        let types = ["systematicReview", "metaAnalysis", "rct", "cochrane", "guideline", "review"]

        for citationType in types {
            let json = """
            {
                "id": "type_test",
                "title": "Test",
                "source": "Test",
                "year": 2023,
                "url": "https://example.com",
                "type": "\(citationType)"
            }
            """

            let data = json.data(using: .utf8)!
            let citation = try JSONDecoder().decode(Citation.self, from: data)
            #expect(citation.type.rawValue == citationType)
        }
    }

    // MARK: - BruxismInfo Tests

    @Test func testBruxismInfoContentDecoding() async throws {
        let json = """
        {
            "sections": [
                {
                    "id": "test_section",
                    "title": "Test Section",
                    "icon": "star.fill",
                    "color": "blue",
                    "content": [
                        {
                            "type": "paragraph",
                            "text": "Test paragraph text",
                            "citationIds": ["citation1"]
                        },
                        {
                            "type": "bulletList",
                            "items": ["Item 1", "Item 2"],
                            "citationIds": []
                        }
                    ]
                }
            ],
            "citations": [],
            "disclaimer": "Test disclaimer"
        }
        """

        let data = json.data(using: .utf8)!
        let info = try JSONDecoder().decode(BruxismInfoData.self, from: data)

        #expect(info.sections.count == 1)
        #expect(info.sections[0].id == "test_section")
        #expect(info.sections[0].title == "Test Section")
        #expect(info.sections[0].content.count == 2)
        #expect(info.disclaimer == "Test disclaimer")
    }

    @Test func testBruxismSectionColorMapping() async throws {
        let colors = ["blue", "orange", "purple", "green", "indigo", "red", "yellow", "pink", "teal"]

        for color in colors {
            let section = BruxismSection(
                id: "test",
                title: "Test",
                icon: "star",
                color: color,
                content: []
            )
            // Just verify it doesn't crash and returns a valid color
            _ = section.swiftUIColor
        }

        // Test unknown color falls back to gray
        let unknownSection = BruxismSection(
            id: "test",
            title: "Test",
            icon: "star",
            color: "unknown",
            content: []
        )
        // This should return gray but we can't easily test Color equality
        _ = unknownSection.swiftUIColor
    }

    // MARK: - Intervention Definition Equality

    @Test func testInterventionDefinitionEquality() async throws {
        let def1 = InterventionDefinition(
            id: "test",
            name: "Test 1",
            emoji: "🧪",
            icon: "star",
            description: "Description 1",
            tier: .strong,
            frequency: .daily,
            trackingType: .binary,
            isRemindable: false
        )

        let def2 = InterventionDefinition(
            id: "test",
            name: "Test 2",  // Different name
            emoji: "🔬",     // Different emoji
            icon: "circle",
            description: "Description 2",
            tier: .lower,    // Different tier
            frequency: .weekly,
            trackingType: .counter,
            isRemindable: true
        )

        // Should be equal because they have the same ID
        #expect(def1 == def2)
    }

    @Test func testInterventionDefinitionInequality() async throws {
        let def1 = InterventionDefinition(
            id: "test1",
            name: "Test",
            icon: "star",
            description: "Description",
            tier: .strong,
            frequency: .daily,
            trackingType: .binary,
            isRemindable: false
        )

        let def2 = InterventionDefinition(
            id: "test2",  // Different ID
            name: "Test",
            icon: "star",
            description: "Description",
            tier: .strong,
            frequency: .daily,
            trackingType: .binary,
            isRemindable: false
        )

        #expect(def1 != def2)
    }

    // MARK: - Citation Display Properties

    @Test func testCitationTypeDisplayNames() async throws {
        #expect(CitationType.systematicReview.displayName == "Systematic Review")
        #expect(CitationType.metaAnalysis.displayName == "Meta-Analysis")
        #expect(CitationType.rct.displayName == "RCT")
        #expect(CitationType.cochrane.displayName == "Cochrane Review")
        #expect(CitationType.guideline.displayName == "Guideline")
        #expect(CitationType.review.displayName == "Review")
    }

    @Test func testCitationTypeIconNames() async throws {
        #expect(CitationType.cochrane.iconName == "checkmark.seal.fill")
        #expect(CitationType.systematicReview.iconName == "doc.text.magnifyingglass")
        #expect(CitationType.metaAnalysis.iconName == "doc.text.magnifyingglass")
        #expect(CitationType.rct.iconName == "flask.fill")
        #expect(CitationType.guideline.iconName == "building.columns.fill")
        #expect(CitationType.review.iconName == "doc.text.fill")
    }

    // MARK: - Intervention Tier Display Properties

    @Test func testInterventionTierDisplayNames() async throws {
        #expect(InterventionTier.strong.displayName == "Strong Evidence")
        #expect(InterventionTier.moderate.displayName == "Moderate Evidence")
        #expect(InterventionTier.lower.displayName == "Lower Evidence")
    }

    @Test func testInterventionTierDescriptions() async throws {
        #expect(InterventionTier.strong.description.contains("clinical research"))
        #expect(InterventionTier.moderate.description.contains("growing research"))
        #expect(InterventionTier.lower.description.contains("anecdotal"))
    }
}
