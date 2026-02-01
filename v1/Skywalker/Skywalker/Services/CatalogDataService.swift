//
//  CatalogDataService.swift
//  Skywalker
//
//  OpenJaw - Loads intervention and bruxism content from bundled JSON files
//

import Foundation
import SwiftUI

// MARK: - JSON Wrapper Structs

private struct InterventionsFileData: Codable {
    let interventions: [InterventionDefinition]
    let citations: [Citation]
}

// MARK: - Catalog Data Service

/// Service that loads intervention catalog and bruxism info from bundled JSON files.
/// This is a value type (struct) because the data is read-only after initialization.
struct CatalogDataService {
    let interventions: [InterventionDefinition]
    let citations: [String: Citation]
    let bruxismInfo: BruxismInfoData?
    let isLoaded: Bool
    let loadError: String?

    init() {
        var loadedInterventions: [InterventionDefinition] = []
        var loadedCitations: [String: Citation] = [:]
        var loadedBruxismInfo: BruxismInfoData?
        var error: String?

        // Load interventions
        if let url = Bundle.main.url(forResource: "interventions", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let fileData = try decoder.decode(InterventionsFileData.self, from: data)
                loadedInterventions = fileData.interventions
                for citation in fileData.citations {
                    loadedCitations[citation.id] = citation
                }
                print("[CatalogDataService] Loaded \(loadedInterventions.count) interventions and \(loadedCitations.count) citations")
            } catch {
                let errorMsg = "Failed to load interventions: \(error.localizedDescription)"
                print("[CatalogDataService] \(errorMsg)")
                print("[CatalogDataService] Error details: \(error)")
            }
        } else {
            error = "Could not find interventions.json in bundle"
            print("[CatalogDataService] \(error!)")
        }

        // Load bruxism info
        if let url = Bundle.main.url(forResource: "bruxism-info", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                loadedBruxismInfo = try decoder.decode(BruxismInfoData.self, from: data)

                // Merge bruxism info citations into main dictionary
                if let info = loadedBruxismInfo {
                    for citation in info.citations {
                        if loadedCitations[citation.id] == nil {
                            loadedCitations[citation.id] = citation
                        }
                    }
                }
                print("[CatalogDataService] Loaded bruxism info with \(loadedBruxismInfo?.sections.count ?? 0) sections")
            } catch {
                print("[CatalogDataService] Failed to load bruxism info: \(error.localizedDescription)")
                print("[CatalogDataService] Error details: \(error)")
            }
        } else {
            print("[CatalogDataService] Could not find bruxism-info.json in bundle")
        }

        self.interventions = loadedInterventions
        self.citations = loadedCitations
        self.bruxismInfo = loadedBruxismInfo
        self.isLoaded = !loadedInterventions.isEmpty
        self.loadError = error
    }

    // MARK: - Public API (matches InterventionCatalog)

    var all: [InterventionDefinition] {
        interventions
    }

    func byTier(_ tier: InterventionTier) -> [InterventionDefinition] {
        interventions.filter { $0.tier == tier }
    }

    func find(byId id: String) -> InterventionDefinition? {
        interventions.first { $0.id == id }
    }

    var remindable: [InterventionDefinition] {
        interventions.filter { $0.isRemindable }
    }

    // MARK: - Citation Lookup

    func citation(byId id: String) -> Citation? {
        citations[id]
    }

    func citations(forIds ids: [String]) -> [Citation] {
        ids.compactMap { citations[$0] }
    }
}

// MARK: - Environment Key

private struct CatalogDataServiceKey: EnvironmentKey {
    static var defaultValue: CatalogDataService = CatalogDataService()
}

extension EnvironmentValues {
    var catalogDataService: CatalogDataService {
        get { self[CatalogDataServiceKey.self] }
        set { self[CatalogDataServiceKey.self] = newValue }
    }
}
