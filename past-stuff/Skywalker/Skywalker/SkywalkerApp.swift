//
//  SkywalkerApp.swift
//  Skywalker
//
//  Created by Tom Humphrey on 30/01/2026.
//

import SwiftUI

@main
struct SkywalkerApp: App {
    private let catalogDataService = CatalogDataService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.catalogDataService, catalogDataService)
        }
    }
}
