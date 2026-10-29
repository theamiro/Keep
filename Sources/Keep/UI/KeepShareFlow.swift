#if canImport(UIKit)
    import UIKit

    /// Asks for an optional note, builds the report, and hands it to the system share sheet. The tester picks the destination.
    /// With `KeepSharing.encryptedOnly` the tester also chooses a password and the report is shared encrypted.
    @MainActor
    enum KeepShareFlow {
        static func start(
            from presenter: UIViewController, scope: KeepExportScope, onFinish: @escaping @MainActor () -> Void
        ) {
            let sharing = KeepRuntime.shared.current?.configuration.sharing ?? .disabled
            guard sharing.allowsShareSheet else {
                onFinish()
                return
            }
            let prompt = KeepSharePrompt.make(
                title: "Share report",
                message: sharing.requiresPassword
                    ? "Optionally describe what went wrong. The report is encrypted with a password you choose, "
                        + "and whoever receives it needs that password to open it."
                    : "Optionally describe what went wrong.",
                asksForNote: true,
                asksForPassword: sharing.requiresPassword,
                onCancel: onFinish
            ) { note, password in
                await export(from: presenter, scope: scope, note: note, password: password, onFinish: onFinish)
            }
            presenter.present(prompt, animated: true)
        }

        private static func export(
            from presenter: UIViewController,
            scope: KeepExportScope,
            note: String?,
            password: String?,
            onFinish: @escaping @MainActor () -> Void
        ) async {
            do {
                let url = try await Keep.exportReport(scope: scope, note: note, password: password)
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activity.completionWithItemsHandler = { _, _, _, _ in
                    // The report's working directory holds only the shared file, so remove it all.
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
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
                alert.addAction(
                    UIAlertAction(title: "OK", style: .default) { _ in
                        Task { @MainActor in onFinish() }
                    })
                presenter.present(alert, animated: true)
            }
        }
    }

    /// The alert that comes before a share: an optional note, and a password typed twice when the share is encrypted.
    /// The Share button stays disabled until the password is long enough and both fields match.
    @MainActor
    enum KeepSharePrompt {
        static func make(
            title: String,
            message: String,
            asksForNote: Bool,
            asksForPassword: Bool,
            onCancel: @escaping @MainActor () -> Void = {},
            onShare: @escaping @MainActor (_ note: String?, _ password: String?) async -> Void
        ) -> UIAlertController {
            let prompt = UIAlertController(title: title, message: message, preferredStyle: .alert)
            if asksForNote {
                prompt.addTextField { field in
                    field.placeholder = "What went wrong?"
                    field.autocapitalizationType = .sentences
                }
            }
            var passwordFields: [UITextField] = []
            if asksForPassword {
                for placeholder in [
                    "Password (\(KeepFileEncryption.minimumPasswordLength)+ characters)", "Repeat password"
                ] {
                    prompt.addTextField { field in
                        field.placeholder = placeholder
                        field.isSecureTextEntry = true
                        field.textContentType = .newPassword
                        passwordFields.append(field)
                    }
                }
            }
            prompt.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    Task { @MainActor in onCancel() }
                })
            let shareTitle = asksForPassword ? "Encrypt and share" : "Share"
            let share = UIAlertAction(title: shareTitle, style: .default) { [weak prompt] _ in
                let fields = prompt?.textFields ?? []
                let note = asksForNote ? fields.first?.text : nil
                let password = asksForPassword ? fields.last?.text : nil
                Task { @MainActor in await onShare(note, password) }
            }
            if asksForPassword {
                share.isEnabled = false
                let fields = passwordFields
                let validate = UIAction { [weak share] _ in
                    let texts = fields.map { $0.text ?? "" }
                    share?.isEnabled = isAcceptable(password: texts[0], repeated: texts[1])
                }
                fields.forEach { $0.addAction(validate, for: .editingChanged) }
            }
            prompt.addAction(share)
            prompt.preferredAction = share
            return prompt
        }

        static func isAcceptable(password: String, repeated: String) -> Bool {
            password.count >= KeepFileEncryption.minimumPasswordLength && password == repeated
        }
    }

#endif
