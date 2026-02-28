import SwiftUI

@main
struct TelocareApp: App {
    @State private var rootViewModel: RootViewModel

    init() {
        let appContainer = AppContainer()
        _rootViewModel = State(initialValue: appContainer.makeRootViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(rootViewModel: rootViewModel)
        }
    }
}
