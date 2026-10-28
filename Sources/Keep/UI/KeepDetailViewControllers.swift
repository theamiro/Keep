#if canImport(UIKit)
    import UIKit

    /// A vertically scrolling detail layout with Copy all and Share actions.
    class KeepDetailViewController: UIViewController, ToastPresentable {
        let scrollView = UIScrollView()
        let contentStack = UIStackView()

        init(title: String) {
            super.init(nibName: nil, bundle: nil)
            self.title = title
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
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped)),
                UIBarButtonItem(title: "Copy all", style: .plain, target: self, action: #selector(copyAllTapped))
            ]
        }

        func buildContent() {}

        func copyAllText() -> String {
            ""
        }

        func shareItems() throws -> [Any] {
            [copyAllText()]
        }

        func clearContent() {
            for view in contentStack.arrangedSubviews {
                contentStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        func addSection(title: String, views: [UIView]) {
            let heading = UILabel()
            heading.text = title.uppercased()
            heading.font = .preferredFont(forTextStyle: .caption1)
            heading.adjustsFontForContentSizeCategory = true
            heading.textColor = .secondaryLabel

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
                let label = UILabel()
                label.text = prefix
                label.font = KeepTheme.codeFont(ofSize: 11)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .secondaryLabel
                label.numberOfLines = 3
                label.lineBreakMode = .byTruncatingTail
                views.append(label)
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

        @objc private func copyAllTapped() {
            copyToPasteboard(copyAllText()) { [weak self] in
                self?.showPopup(message: "Copied to clipboard")
            }
        }

        @objc private func shareTapped() {
            do {
                let activity = try UIActivityViewController(activityItems: shareItems(), applicationActivities: nil)
                activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
                present(activity, animated: true)
            } catch {
                showPopup(message: "Could not prepare share item")
            }
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
            let header = UIStackView()
            header.axis = .vertical
            header.alignment = .leading
            header.spacing = 9

            let level = PillLabel(
                text: entry.level.shortCode,
                color: entry.level.uiColor,
                background: entry.level.uiColor.withAlphaComponent(0.12)
            )
            let timestamp = UILabel()
            timestamp.text = KeepCodec.displayString(for: entry.timestamp)
            timestamp.font = KeepTheme.codeFont(ofSize: 11)
            timestamp.adjustsFontForContentSizeCategory = true
            timestamp.textColor = .secondaryLabel
            header.addArrangedSubview(level)
            header.addArrangedSubview(timestamp)

            let message = makeSelectableTextView(entry.message, font: .preferredFont(forTextStyle: .body))
            addSection(title: "Message", views: [header, message])

            let fields = [
                KeepKeyValue("Source", entry.source),
                KeepKeyValue("Location", "\(entry.file):\(entry.line) · \(entry.function)"),
                KeepKeyValue("Label", entry.label),
                KeepKeyValue("Tag", entry.tag),
                KeepKeyValue("Pinned", entry.isPinned ? "Yes" : "No")
            ]
            addSection(title: "Details", views: [KeyValueListView(rows: fields)])

            for key in entry.metadata.keys.sorted() {
                guard let value = entry.metadata[key] else { continue }
                addMetadataSection(key: key, value: value)
            }
        }

        override func copyAllText() -> String {
            Self.describe(entry)
        }

        private func addMetadataSection(key: String, value: JSONValue) {
            switch value {
            case let .string(string):
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
#endif
