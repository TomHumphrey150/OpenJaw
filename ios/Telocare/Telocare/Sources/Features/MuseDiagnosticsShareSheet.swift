import SwiftUI
import UIKit

struct MuseDiagnosticsShareSheet: UIViewControllerRepresentable {
    let fileURLs: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        _ = controller
        _ = context
    }
}
