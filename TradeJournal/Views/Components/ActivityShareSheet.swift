import SwiftUI
import UIKit

/// Brug naar `UIActivityViewController`, zodat een backup of CSV via de iOS
/// share sheet gedeeld of met "Bewaar in Bestanden" opgeslagen kan worden.
///
/// `onComplete` krijgt `true` als de gebruiker een actie voltooid heeft
/// (en dus niet op annuleren tikte).
struct ActivityShareSheet: UIViewControllerRepresentable {

    let items: [Any]
    var onComplete: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
