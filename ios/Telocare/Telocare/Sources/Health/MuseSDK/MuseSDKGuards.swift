import Foundation

enum MuseSDKGuards {
    static var defaultSessionService: MuseSessionService {
#if targetEnvironment(simulator)
        return MockMuseSessionService()
#else
        guard NSClassFromString("IXNMuseManagerIos") != nil else {
            return UnavailableMuseSessionService()
        }

        return MuseSDKSessionService()
#endif
    }
}
