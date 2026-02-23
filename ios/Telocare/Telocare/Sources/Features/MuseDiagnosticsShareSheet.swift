import SwiftUI
import UIKit

struct MuseDiagnosticsShareSheet: UIViewControllerRepresentable {
    let fileURLs: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            _ = returnedItems
            if let error {
                MuseDiagnosticsLogger.error("Diagnostics share failed: \(error.localizedDescription)")
                return
            }

            if completed {
                MuseDiagnosticsLogger.info(
                    "Diagnostics share completed via \(activityType?.rawValue ?? "unknown")"
                )
                return
            }

            MuseDiagnosticsLogger.info("Diagnostics share cancelled")
        }

        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        _ = controller
        _ = context
    }
}
