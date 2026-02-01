//
//  Skywalker_WatchApp.swift
//  Skywalker-Watch Watch App
//
//  Bruxism Biofeedback - Watch app entry point
//

import SwiftUI

@main
struct Skywalker_Watch_Watch_AppApp: App {
    @State private var connectivityManager = WatchConnectivityManager()
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                // Tab 0: Sleep mode (black screen)
                SleepView(connectivityManager: connectivityManager)
                    .tag(0)

                // Tab 1: Debug/status view
                ContentView(connectivityManager: connectivityManager)
                    .tag(1)
            }
            .tabViewStyle(.verticalPage)  // Swipe up/down to switch
            .onAppear {
                // Request extended runtime to keep app alive
                connectivityManager.requestExtendedRuntime()
            }
        }
    }
}
