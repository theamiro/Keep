#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// A vertically scrolling detail layout. Its Share button opens a menu built from `shareMenuActions()`.
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

        func configureNavigationItems() {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .action, target: self, action: #selector(shareTapped)
            )
        }

        func buildContent() {}

        func copyAllText() -> String {
            ""
        }

        func shareItems() throws -> [Any] {
            [copyAllText()]
        }

        /// The actions in the Share menu. Subclasses override this to add or replace actions.
        func shareMenuActions() -> [UIAlertAction] {
            [
                shareMenuAction("Copy all") { [weak self] in self?.copyAllToPasteboard() },
                shareMenuAction("Share text") { [weak self] in self?.presentShareItems() }
            ]
        }

        /// A Share menu action. Its handler runs on the main actor, as the other UIKit handlers do.
        func shareMenuAction(_ title: String, handler: @escaping @MainActor @Sendable () -> Void) -> UIAlertAction {
            UIAlertAction(title: title, style: .default) { _ in
                Task { @MainActor in handler() }
            }
        }

        /// Shows the share sheet for `shareItems()`, or a popup when the items cannot be prepared.
        func presentShareItems() {
            do {
                presentActivity(items: try shareItems())
            } catch {
                showPopup(message: "Could not prepare share item")
            }
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
            shareMenuActions().forEach(menu.addAction)
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

        override func shareMenuActions() -> [UIAlertAction] {
            super.shareMenuActions() + [
                shareMenuAction("Share as file") { [weak self] in self?.presentLogFile() }
            ]
        }

        /// Writes the log to a text file in the temporary directory and shares it.
        private func presentLogFile() {
            let directory = FileManager.default.temporaryDirectory
            let url = directory.appendingPathComponent("keep-log-\(entry.id.prefix(8)).txt")
            do {
                try copyAllText().write(to: url, atomically: true, encoding: .utf8)
                presentActivity(items: [url])
            } catch {
                showPopup(message: "Could not prepare log file")
            }
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
