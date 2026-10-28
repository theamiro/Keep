#if canImport(UIKit)
    import UIKit

    /// Asks for an optional note, builds the report, and hands it to the system share sheet. The tester picks the destination.
    @MainActor
    enum KeepShareFlow {
        static func start(from presenter: UIViewController, scope: KeepExportScope, onFinish: @escaping @MainActor () -> Void) {
            let prompt = UIAlertController(
                title: "Share report",
                message: "Optionally describe what went wrong.",
                preferredStyle: .alert
            )
            prompt.addTextField { field in
                field.placeholder = "What went wrong?"
                field.autocapitalizationType = .sentences
            }
            prompt.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                Task { @MainActor in onFinish() }
            })
            prompt.addAction(UIAlertAction(title: "Share", style: .default) { [weak prompt] _ in
                let note = prompt?.textFields?.first?.text
                Task { @MainActor in
                    await export(from: presenter, scope: scope, note: note, onFinish: onFinish)
                }
            })
            presenter.present(prompt, animated: true)
        }

        private static func export(
            from presenter: UIViewController,
            scope: KeepExportScope,
            note: String?,
            onFinish: @escaping @MainActor () -> Void
        ) async {
            do {
                let url = try await Keep.exportReport(scope: scope, note: note)
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activity.completionWithItemsHandler = { _, _, _, _ in
                    Task { @MainActor in onFinish() }
                }
                activity.popoverPresentationController?.sourceView = presenter.view
                activity.popoverPresentationController?.sourceRect = CGRect(
                    x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1
                )
                presenter.present(activity, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: "Could not create report",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    Task { @MainActor in onFinish() }
                })
                presenter.present(alert, animated: true)
            }
        }
    }

#endif
