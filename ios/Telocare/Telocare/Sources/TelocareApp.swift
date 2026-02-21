import SwiftUI

@main
struct TelocareApp: App {
    @StateObject private var rootViewModel: RootViewModel

    init() {
        let appContainer = AppContainer()
        _rootViewModel = StateObject(wrappedValue: appContainer.makeRootViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(rootViewModel: rootViewModel)
        }
    }
}
