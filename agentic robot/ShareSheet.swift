import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {

        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        // iPad / iOS 26-safe popover anchoring
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
}
