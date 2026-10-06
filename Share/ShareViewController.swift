import RemaCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        AppFonts.register()
        loadText { [weak self] text in
            self?.show(text)
        }
    }

    private func show(_ text: String) {
        let screen = ShareScreen(
            source: text,
            snapshot: SharedStore.load(),
            onCancel: { [weak self] in self?.finish(saved: false) },
            onSaved: { [weak self] in self?.finish(saved: true) }
        )
        let host = UIHostingController(rootView: screen)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func loadText(_ completion: @escaping (String) -> Void) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let type = UTType.plainText.identifier
        guard let provider = items.flatMap({ $0.attachments ?? [] }).first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else {
            completion(items.first?.attributedContentText?.string ?? "")
            return
        }
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
            let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async { completion(text) }
        }
    }

    private func finish(saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
