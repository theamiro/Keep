#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// An entry in a detail's Share menu. The kind decides whether `KeepConfiguration.sharing` allows it, and how a
    /// file is shared.
    struct KeepDetailAction {
        enum Kind {
            /// Copies to the pasteboard. Always allowed.
            case copy(@MainActor @Sendable () -> Void)
            /// Shares text through the share sheet. Only when unencrypted sharing is allowed.
            case shareText(@MainActor @Sendable () -> String)
            /// Shares a file through the share sheet, encrypted when the configuration requires it.
            case shareFile(name: String, contents: @MainActor @Sendable () throws -> Data)
        }

        let title: String
        let kind: Kind

        func isAllowed(by sharing: KeepSharing) -> Bool {
            switch kind {
            case .copy: return true
            case .shareText: return sharing.allowsUnencrypted
            case .shareFile: return sharing.allowsShareSheet
            }
        }
    }

    /// A vertically scrolling detail layout. Its Share button opens a menu built from `detailActions()`, without
    /// the actions `KeepConfiguration.sharing` does not allow.
    class KeepDetailViewController: UIViewController, ToastPresentable {
        let scrollView = UIScrollView()
        let contentStack = UIStackView()

        init(title: String) {
            super.init(nibName: nil, bundle: nil)
            self.title = title
            // Keep the viewer's tab bar out of the way while a detail is open.
            hidesBottomBarWhenPushed = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            configureLayout()
            configureNavigationItems()
            buildContent()
        }

        var sharing: KeepSharing {
            KeepRuntime.shared.current?.configuration.sharing ?? .disabled
        }

        func configureNavigationItems() {
            // Without the share sheet the menu only copies, so the button shows a copy icon instead.
            navigationItem.rightBarButtonItem =
                sharing.allowsShareSheet
                ? UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))
                : UIBarButtonItem(
                    image: UIImage(systemName: "doc.on.doc"),
                    style: .plain,
                    target: self,
                    action: #selector(shareTapped)
                )
            navigationItem.rightBarButtonItem?.accessibilityLabel = sharing.allowsShareSheet ? "Share" : "Copy"
        }

        func buildContent() {}

        func copyAllText() -> String {
            ""
        }

        /// The actions in the Share menu. Subclasses override this to add or replace actions.
        func detailActions() -> [KeepDetailAction] {
            [
                KeepDetailAction(title: "Copy all", kind: .copy { [weak self] in self?.copyAllToPasteboard() }),
                KeepDetailAction(title: "Share text", kind: .shareText { [weak self] in self?.copyAllText() ?? "" })
            ]
        }

        private func run(_ action: KeepDetailAction) {
            switch action.kind {
            case .copy(let copy):
                copy()
            case .shareText(let text):
                presentActivity(items: [text()])
            case .shareFile(let name, let contents):
                do {
                    let data = try contents()
                    if sharing.requiresPassword {
                        askPasswordAndShare(data, fileName: name)
                    } else {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try data.write(to: url, options: .atomic)
                        presentActivity(items: [url])
                    }
                } catch {
                    showPopup(message: "Could not prepare file")
                }
            }
        }

        /// Asks for a password, then shares `data` as an encrypted `<fileName>.keep`. Only the encrypted file is
        /// written.
        private func askPasswordAndShare(_ data: Data, fileName: String) {
            let prompt = KeepSharePrompt.make(
                title: "Encrypt file",
                message: "Choose a password. Whoever receives the file needs it to open it.",
                asksForNote: false,
                asksForPassword: true
            ) { [weak self] _, password in
                guard let password else { return }
                do {
                    let url = try await Task.detached(priority: .userInitiated) {
                        try KeepFileEncryption.writeEncryptedFile(data, fileName: fileName, password: password)
                    }.value
                    self?.presentActivity(items: [url])
                } catch {
                    self?.showPopup(message: "Could not encrypt file")
                }
            }
            present(prompt, animated: true)
        }

        /// Shows the system share sheet. File URLs in `items` are removed when the sheet closes, so shared
        /// files do not stay on disk. Keep passes only files it wrote to the temporary directory.
        func presentActivity(items: [Any]) {
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            activity.completionWithItemsHandler = { _, _, _, _ in
                for case let url as URL in items where url.isFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            present(activity, animated: true)
        }

        func copyAllToPasteboard() {
            copyToPasteboard(copyAllText()) { [weak self] in
                self?.showPopup(message: "Copied to clipboard")
            }
        }

        func clearContent() {
            for view in contentStack.arrangedSubviews {
                contentStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        /// Adds a section whose content is SwiftUI.
        func addSection<Content: View>(title: String, @ViewBuilder content: () -> Content) {
            contentStack.addArrangedSubview(KeepHostingView(KeepDetailSection(title: title, content: content)))
        }

        /// Adds a section whose content includes UIKit views, such as selectable text.
        func addSection(title: String, views: [UIView]) {
            let heading = KeepHostingView(KeepSectionHeading(title: title))
            let section = UIStackView(arrangedSubviews: [heading] + views)
            section.axis = .vertical
            section.alignment = .fill
            section.spacing = 8
            contentStack.addArrangedSubview(section)
        }

        func addCodeBlock(
            title: String,
            text: String,
            rawText: String? = nil,
            isJSON: Bool = false,
            byteCount: Int? = nil,
            prefix: String? = nil
        ) {
            var views: [UIView] = []
            if let prefix, !prefix.isEmpty {
                views.append(KeepHostingView(CodeBlockPrefix(text: prefix)))
            }
            let codeBlock = CodeBlockView(
                title: title,
                text: text,
                rawText: rawText,
                isJSON: isJSON,
                byteCount: byteCount
            )
            codeBlock.onCopy = { [weak self] in self?.showPopup(message: "Copied to clipboard") }
            views.append(codeBlock)
            let blockStack = UIStackView(arrangedSubviews: views)
            blockStack.axis = .vertical
            blockStack.spacing = 6
            contentStack.addArrangedSubview(blockStack)
        }

        func makeSelectableTextView(_ text: String, font: UIFont, textColor: UIColor = .label) -> UITextView {
            let textView = UITextView()
            textView.text = text
            textView.font = font
            textView.textColor = textColor
            textView.backgroundColor = .clear
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.setContentCompressionResistancePriority(.required, for: .vertical)
            let width = max(280, view.bounds.width - 36)
            let height = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            textView.heightAnchor.constraint(equalToConstant: max(font.lineHeight, height)).isActive = true
            return textView
        }

        @objc private func shareTapped() {
            let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            for action in detailActions() where action.isAllowed(by: sharing) {
                menu.addAction(
                    UIAlertAction(title: action.title, style: .default) { [weak self] _ in
                        Task { @MainActor in self?.run(action) }
                    })
            }
            menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(menu, animated: true)
        }

        private func configureLayout() {
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.axis = .vertical
            contentStack.alignment = .fill
            contentStack.spacing = 18

            view.addSubview(scrollView)
            scrollView.addSubview(contentStack)
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
                contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
                contentStack.trailingAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16
                ),
                contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
            ])
        }
    }

    final class LogDetailViewController: KeepDetailViewController {
        private let entry: LogEntry

        init(entry: LogEntry) {
            self.entry = entry
            super.init(title: "Log")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func buildContent() {
            // The message stays a UITextView so testers can select part of it.
            let message = makeSelectableTextView(entry.message, font: .preferredFont(forTextStyle: .body))
            addSection(title: "Message", views: [KeepHostingView(LogDetailHeader(entry: entry)), message])

            let fields = [
                KeepKeyValue("Source", entry.source),
                KeepKeyValue("Location", "\(entry.file):\(entry.line) · \(entry.function)"),
                KeepKeyValue("Label", entry.label),
                KeepKeyValue("Tag", entry.tag),
                KeepKeyValue("Pinned", entry.isPinned ? "Yes" : "No")
            ]
            addSection(title: "Details") {
                KeyValueList(rows: fields)
            }

            for key in entry.metadata.keys.sorted() {
                guard let value = entry.metadata[key] else { continue }
                addMetadataSection(key: key, value: value)
            }
        }

        override func copyAllText() -> String {
            Self.describe(entry)
        }

        override func detailActions() -> [KeepDetailAction] {
            let text = copyAllText()
            return super.detailActions() + [
                KeepDetailAction(
                    title: "Share as file",
                    kind: .shareFile(name: "keep-log-\(entry.id.prefix(8)).txt") { Data(text.utf8) }
                )
            ]
        }

        private func addMetadataSection(key: String, value: JSONValue) {
            switch value {
            case .string(let string):
                if string.utf8.count >= CodeBlockView.formattingThreshold {
                    if let candidate = JSONFormatter.embeddedCandidate(string) {
                        addCodeBlock(
                            title: key,
                            text: candidate.json,
                            rawText: string,
                            isJSON: true,
                            byteCount: string.utf8.count,
                            prefix: candidate.prefix
                        )
                    } else {
                        addCodeBlock(title: key, text: string, rawText: string, byteCount: string.utf8.count)
                    }
                    return
                }
                if let embedded = JSONFormatter.splitEmbedded(string) {
                    addCodeBlock(
                        title: key,
                        text: embedded.json,
                        rawText: string,
                        isJSON: true,
                        byteCount: string.utf8.count,
                        prefix: embedded.prefix
                    )
                } else if JSONFormatter.format(string) != nil {
                    addCodeBlock(title: key, text: string, rawText: string, isJSON: true, byteCount: string.utf8.count)
                } else {
                    addCodeBlock(title: key, text: string, rawText: string, byteCount: string.utf8.count)
                }
            case .object, .array:
                let encodedData = try? KeepCodec.encoder().encode(value)
                let encoded = encodedData.flatMap { String(bytes: $0, encoding: .utf8) } ?? value.text
                addCodeBlock(
                    title: key,
                    text: encoded,
                    rawText: encoded,
                    isJSON: true,
                    byteCount: encoded.utf8.count
                )
            }
        }

        private static func describe(_ entry: LogEntry) -> String {
            var lines = [
                "Time:      \(KeepCodec.displayString(for: entry.timestamp))",
                "Level:     \(entry.level.rawValue.uppercased())",
                "Label:     \(entry.label)",
                "Tag:       \(entry.tag)",
                "Source:    \(entry.source)",
                "Location:  \(entry.file):\(entry.line) \(entry.function)",
                "Pinned:    \(entry.isPinned ? "yes" : "no")",
                "",
                "MESSAGE",
                entry.message
            ]
            if !entry.metadata.isEmpty {
                lines += ["", "METADATA", entry.metadata.prettyJSON()]
            }
            return lines.joined(separator: "\n")
        }
    }

    #if DEBUG
        @available(iOS 17, *)
        #Preview("Error with JSON metadata") {
            UINavigationController(rootViewController: LogDetailViewController(entry: PreviewSamples.error))
        }

        @available(iOS 17, *)
        #Preview("Pinned warning") {
            UINavigationController(rootViewController: LogDetailViewController(entry: PreviewSamples.pinnedWarning))
        }
    #endif
#endif
