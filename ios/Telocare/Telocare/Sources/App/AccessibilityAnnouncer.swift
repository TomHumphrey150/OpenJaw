import UIKit

struct AccessibilityAnnouncer {
    let announce: (String) -> Void

    static let voiceOver = AccessibilityAnnouncer { message in
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
