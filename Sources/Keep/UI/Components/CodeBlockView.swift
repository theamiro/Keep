#if canImport(UIKit) && KEEP_RUNESTONE
    import Runestone
    import TreeSitterJSONRunestone
    import UIKit

    final class CodeBlockView: UIView, UIContextMenuInteractionDelegate {
        static var defaultWrapEnabled = true
        static let formattingThreshold = 64 * 1024
        private static let renderLineLimit = 2000

        var onCopy: (() -> Void)?

        private let title: String
        private let rawText: String
        private let byteCount: Int
        private let isJSON: Bool
        private let headerTitle = UILabel()
        private let subtitleLabel = UILabel()
        private let wrapButton = UIButton(type: .system)
        private let copyButton = UIButton(type: .system)
        private let horizontalScroll = UIScrollView()
        private let textView = TextView()
        private let showAllButton = UIButton(type: .system)
        private var heightConstraint: NSLayoutConstraint!
        private var wrappingWidthConstraint: NSLayoutConstraint!
        private var fixedWidthConstraint: NSLayoutConstraint!
        private var isWrapping = CodeBlockView.defaultWrapEnabled
        private var isShowingAll = false
        private var formattedText: String?
        private var fullText = ""
        private var displayedText = ""
        private var calculatedFont = KeepTheme.codeFont()
        private var displayedLineCount = 1

        init(
            title: String,
            text: String,
            rawText: String? = nil,
            isJSON: Bool = false,
            byteCount: Int? = nil
        ) {
            self.title = title
            self.rawText = rawText ?? text
            self.byteCount = byteCount ?? (rawText ?? text).lengthOfBytes(using: .utf8)
            self.isJSON = isJSON
            super.init(frame: .zero)
            configureView()

            let sourceBytes = text.lengthOfBytes(using: .utf8)
            if isJSON, sourceBytes >= Self.formattingThreshold {
                setDisplayedText(text, syntaxHighlighted: false)
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let formatted = JSONFormatter.format(text)?.text
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.formattedText = formatted
                        self.setDisplayedText(formatted ?? text, syntaxHighlighted: formatted != nil)
                    }
                }
            } else {
                let formatted = isJSON ? JSONFormatter.format(text)?.text : nil
                formattedText = formatted
                setDisplayedText(formatted ?? text, syntaxHighlighted: formatted != nil)
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateTextMetrics()
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            guard traitCollection.preferredContentSizeCategory
                != previousTraitCollection?.preferredContentSizeCategory
            else {
                return
            }
            calculatedFont = KeepTheme.codeFont()
            textView.theme = KeepCodeTheme()
            updateTextMetrics()
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(children: [
                    UIAction(title: "Copy Formatted", image: UIImage(systemName: "doc.on.doc")) { _ in
                        self?.copyFormatted()
                    },
                    UIAction(title: "Copy Raw", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                        self?.copyRaw()
                    }
                ])
            }
        }

        private func configureView() {
            backgroundColor = .secondarySystemBackground
            layer.borderColor = UIColor.separator.cgColor
            layer.borderWidth = 0.5
            layer.cornerRadius = 9
            clipsToBounds = true

            let header = makeHeader()
            configureEditor()
            configureShowAllButton()
            addContentStack(header: header)
            addInteraction(UIContextMenuInteraction(delegate: self))
            applyWrappingState()
        }

        private func makeHeader() -> UIStackView {
            let labels = UIStackView(arrangedSubviews: [headerTitle, subtitleLabel])
            labels.axis = .vertical
            labels.spacing = 2

            headerTitle.text = title
            headerTitle.font = .preferredFont(forTextStyle: .subheadline)
            headerTitle.adjustsFontForContentSizeCategory = true
            headerTitle.textColor = .label
            headerTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
            subtitleLabel.adjustsFontForContentSizeCategory = true
            subtitleLabel.textColor = .secondaryLabel

            configure(button: wrapButton, symbol: "text.alignleft", action: #selector(wrapTapped))
            configure(button: copyButton, symbol: "doc.on.doc", action: #selector(copyTapped))
            wrapButton.accessibilityLabel = isWrapping ? "Disable wrapping" : "Wrap code"
            let buttons = UIStackView(arrangedSubviews: [wrapButton, copyButton])
            buttons.axis = .horizontal
            buttons.spacing = 7
            buttons.alignment = .center

            let header = UIStackView(arrangedSubviews: [labels, buttons])
            header.axis = .horizontal
            header.alignment = .center
            header.spacing = 10
            header.translatesAutoresizingMaskIntoConstraints = false
            return header
        }

        private func configureEditor() {
            horizontalScroll.translatesAutoresizingMaskIntoConstraints = false
            horizontalScroll.backgroundColor = .secondarySystemBackground
            horizontalScroll.alwaysBounceHorizontal = false
            horizontalScroll.alwaysBounceVertical = false
            horizontalScroll.showsHorizontalScrollIndicator = true
            horizontalScroll.isDirectionalLockEnabled = true

            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.backgroundColor = .clear
            textView.theme = KeepCodeTheme()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.showLineNumbers = false
            textView.textContainerInset = UIEdgeInsets(top: 10, left: 11, bottom: 10, right: 11)
            textView.lineBreakMode = .byCharWrapping

            horizontalScroll.addSubview(textView)
            wrappingWidthConstraint = textView.widthAnchor.constraint(
                equalTo: horizontalScroll.frameLayoutGuide.widthAnchor
            )
            fixedWidthConstraint = textView.widthAnchor.constraint(equalToConstant: 0)
            heightConstraint = textView.heightAnchor.constraint(equalToConstant: 1)
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.trailingAnchor),
                textView.topAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.topAnchor),
                textView.bottomAnchor.constraint(equalTo: horizontalScroll.contentLayoutGuide.bottomAnchor),
                heightConstraint
            ])
        }

        private func configureShowAllButton() {
            showAllButton.setTitle("Show all", for: .normal)
            showAllButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            showAllButton.addTarget(self, action: #selector(showAllTapped), for: .touchUpInside)
            showAllButton.contentHorizontalAlignment = .leading
            showAllButton.isHidden = true
        }

        private func addContentStack(header: UIStackView) {
            let stack = UIStackView(arrangedSubviews: [header, horizontalScroll, showAllButton])
            stack.axis = .vertical
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                header.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
                horizontalScroll.heightAnchor.constraint(equalTo: textView.heightAnchor)
            ])
        }

        private func setDisplayedText(_ text: String, syntaxHighlighted: Bool) {
            fullText = text
            let allLines = text.components(separatedBy: "\n")
            let shouldShowAllButton = allLines.count > Self.renderLineLimit && !isShowingAll
            let visibleText = shouldShowAllButton
                ? allLines.prefix(Self.renderLineLimit).joined(separator: "\n")
                : text
            formattedText = syntaxHighlighted ? text : formattedText
            displayedText = visibleText
            displayedLineCount = max(1, visibleText.components(separatedBy: "\n").count)
            showAllButton.isHidden = !shouldShowAllButton
            textView.text = visibleText
            textView.isLineWrappingEnabled = isWrapping
            subtitleLabel.text = "\(isJSON ? "JSON" : "TEXT") · \(ByteCountDisplay.string(byteCount))"
            if syntaxHighlighted {
                textView.setLanguageMode(TreeSitterLanguageMode(language: TreeSitterLanguage.json))
            } else {
                textView.setLanguageMode(PlainTextLanguageMode())
            }
            updateTextMetrics()
        }
    }

    private extension CodeBlockView {
        func configure(button: UIButton, symbol: String, action: Selector) {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .secondaryLabel
            button.addTarget(self, action: action, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 32)
            ])
        }

        private func updateTextMetrics() {
            guard horizontalScroll.bounds.width > 0 else { return }
            let textWidth = calculatedWidth(for: displayedText)
            let width = max(horizontalScroll.bounds.width, textWidth)
            heightConstraint.constant = CGFloat(renderedLineCount) * calculatedFont.lineHeight + 20
            if isWrapping {
                fixedWidthConstraint.isActive = false
                wrappingWidthConstraint.isActive = true
            } else {
                wrappingWidthConstraint.isActive = false
                fixedWidthConstraint.constant = width
                fixedWidthConstraint.isActive = true
            }
        }

        private func calculatedWidth(for text: String) -> CGFloat {
            guard !isWrapping else { return horizontalScroll.bounds.width }
            let attributes = [NSAttributedString.Key.font: calculatedFont]
            let longestLine = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { ($0 as NSString).size(withAttributes: attributes).width }
                .max() ?? 0
            return ceil(longestLine + 24)
        }

        private var renderedLineCount: Int {
            guard isWrapping else { return displayedLineCount }
            let width = max(1, horizontalScroll.bounds.width - 22)
            let bounds = (displayedText as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: calculatedFont],
                context: nil
            )
            return max(displayedLineCount, Int(ceil(bounds.height / calculatedFont.lineHeight)))
        }

        private func applyWrappingState() {
            Self.defaultWrapEnabled = isWrapping
            textView.isLineWrappingEnabled = isWrapping
            wrapButton.accessibilityLabel = isWrapping ? "Disable wrapping" : "Wrap code"
            updateTextMetrics()
        }

        @objc func wrapTapped() {
            isWrapping.toggle()
            applyWrappingState()
        }

        @objc func copyTapped() {
            copyFormatted()
        }

        @objc func showAllTapped() {
            isShowingAll = true
            setDisplayedText(fullText, syntaxHighlighted: isJSON && formattedText != nil)
        }

        func copyFormatted() {
            copyToPasteboard(fullText.isEmpty ? rawText : fullText) { [weak self] in self?.onCopy?() }
        }

        func copyRaw() {
            copyToPasteboard(rawText) { [weak self] in self?.onCopy?() }
        }
    }
#elseif canImport(UIKit)
    import UIKit

    final class CodeBlockView: UIView {
        static var defaultWrapEnabled = true
        static let formattingThreshold = 64 * 1024

        var onCopy: (() -> Void)?

        private let rawText: String
        private let textView = UITextView()

        init(
            title: String,
            text: String,
            rawText: String? = nil,
            isJSON: Bool = false,
            byteCount: Int? = nil
        ) {
            self.rawText = rawText ?? text
            super.init(frame: .zero)

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .preferredFont(forTextStyle: .subheadline)
            titleLabel.textColor = .label

            let copyButton = UIButton(type: .system)
            copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
            copyButton.accessibilityLabel = "Copy block"
            copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

            let header = UIStackView(arrangedSubviews: [titleLabel, copyButton])
            header.axis = .horizontal
            header.alignment = .center
            header.distribution = .equalSpacing

            textView.text = text
            textView.font = KeepTheme.codeFont()
            textView.backgroundColor = .clear
            textView.isEditable = false
            textView.isScrollEnabled = false
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

            let stack = UIStackView(arrangedSubviews: [header, textView])
            stack.axis = .vertical
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
            ])
            backgroundColor = .secondarySystemBackground
            layer.borderWidth = 0.5
            layer.borderColor = UIColor.separator.cgColor
            layer.cornerRadius = 9
            isAccessibilityElement = false
            _ = isJSON
            _ = byteCount
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        @objc private func copyTapped() {
            copyToPasteboard(rawText) { [weak self] in self?.onCopy?() }
        }
    }
#endif
