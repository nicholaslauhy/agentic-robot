import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {

    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {

        // Create a temporary export copy
        let tempURL = createTemporaryCopy(of: fileURL)

        let itemSource = PDFShareItemSource(url: tempURL)

        let controller = UIActivityViewController(
            activityItems: [itemSource],
            applicationActivities: nil
        )

        // iPad-safe presentation
        if let popover = controller.popoverPresentationController {

            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

            let window = scene?.windows.first

            popover.sourceView = window

            if let window {
                popover.sourceRect = CGRect(
                    x: window.bounds.midX,
                    y: window.bounds.midY,
                    width: 0,
                    height: 0
                )
            }

            popover.permittedArrowDirections = []
        }

        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}

    // MARK: - Temp Export

    private func createTemporaryCopy(of url: URL) -> URL {

        let tempDir = FileManager.default.temporaryDirectory

        let tempURL = tempDir.appendingPathComponent(
            url.lastPathComponent
        )

        do {

            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }

            try FileManager.default.copyItem(
                at: url,
                to: tempURL
            )

            return tempURL

        } catch {

            print("Failed to create temp share copy:", error)

            return url
        }
    }
}

// MARK: - Activity Item Source

final class PDFShareItemSource: NSObject, UIActivityItemSource {

    let url: URL

    init(url: URL) {
        self.url = url
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {

        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {

        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {

        UTType.pdf.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {

        "Police Damage Report"
    }
}
