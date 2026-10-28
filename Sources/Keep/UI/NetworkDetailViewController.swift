#if canImport(UIKit)
    import UIKit

    final class NetworkDetailViewController: KeepDetailViewController {
        private let transaction: KeepHTTPTransaction
        private let segments = UISegmentedControl(items: ["Overview", "Request", "Response"])

        init(transaction: KeepHTTPTransaction) {
            self.transaction = transaction
            super.init(title: "\(transaction.method) \(transaction.statusCode.map(String.init) ?? "ERR")")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func configureNavigationItems() {
            segments.selectedSegmentIndex = 0
            segments.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
            navigationItem.titleView = segments
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTappedFromSubclass)),
                UIBarButtonItem(
                    title: "Copy all", style: .plain, target: self, action: #selector(copyAllTappedFromSubclass)
                ),
                UIBarButtonItem(title: "cURL", style: .plain, target: self, action: #selector(copyCurl))
            ]
        }

        override func buildContent() {
            renderSegment()
        }

        override func copyAllText() -> String {
            [
                overviewText(),
                Self.describe(headers: transaction.requestHeaders, body: transaction.requestBody),
                Self.describe(headers: transaction.responseHeaders, body: transaction.responseBody)
            ].joined(separator: "\n\n")
        }

        override func shareItems() throws -> [Any] {
            let data = try HAR.data(for: [transaction], creatorVersion: KeepInfo.version)
            let fileName = "keep-request-\(transaction.id.prefix(8)).har"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url)
            return [url]
        }

        @objc private func segmentChanged() {
            renderSegment()
        }

        @objc private func copyCurl() {
            copyToPasteboard(transaction.curlCommand) { [weak self] in
                self?.showPopup(message: "cURL copied")
            }
        }

        @objc private func shareTappedFromSubclass() {
            do {
                let activity = try UIActivityViewController(
                    activityItems: shareItems(), applicationActivities: nil
                )
                activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
                present(activity, animated: true)
            } catch {
                showPopup(message: "Could not prepare HAR file")
            }
        }

        @objc private func copyAllTappedFromSubclass() {
            copyToPasteboard(copyAllText()) { [weak self] in
                self?.showPopup(message: "Copied to clipboard")
            }
        }

        private func renderSegment() {
            clearContent()
            switch segments.selectedSegmentIndex {
            case 1:
                buildRequestResponse(
                    headers: transaction.requestHeaders,
                    body: transaction.requestBody,
                    title: "Request"
                )
            case 2:
                buildRequestResponse(
                    headers: transaction.responseHeaders,
                    body: transaction.responseBody,
                    title: "Response"
                )
            default: buildOverview()
            }
        }

        private func buildOverview() {
            let statusColor = KeepTheme.statusColor(transaction.statusCode)
            let status = PillLabel(
                text: transaction.statusCode.map(String.init) ?? "ERR",
                color: statusColor,
                background: statusColor.withAlphaComponent(0.12)
            )
            let method = PillLabel(
                text: transaction.method.uppercased(),
                color: .systemIndigo,
                background: UIColor.systemIndigo.withAlphaComponent(0.12)
            )
            let duration = UILabel()
            duration.text = String(format: "%.0f ms", transaction.duration * 1000)
            duration.font = KeepTheme.codeFont(ofSize: 11)
            duration.textColor = .secondaryLabel
            let summary = UIStackView(arrangedSubviews: [method, status, UIView(), duration])
            summary.axis = .horizontal
            summary.alignment = .center
            summary.spacing = 8

            addSection(title: "Transaction", views: [summary])
            addCodeBlock(title: "URL", text: transaction.url, byteCount: transaction.url.utf8.count)

            if let components = URLComponents(string: transaction.url),
               let queryItems = components.queryItems,
               !queryItems.isEmpty {
                addSection(title: "Query Parameters", views: [KeyValueListView(rows: queryItems.map {
                    KeepKeyValue($0.name, $0.value ?? "")
                })])
            }

            var details = [
                KeepKeyValue("Started", KeepCodec.displayString(for: transaction.startedAt)),
                KeepKeyValue("Duration", String(format: "%.1f ms", transaction.duration * 1000)),
                KeepKeyValue("Client", transaction.label)
            ]
            if let requestSize = transaction.requestBody?.byteCount {
                details.append(KeepKeyValue("Request Size", ByteCountDisplay.string(requestSize)))
            }
            if let responseSize = transaction.responseBody?.byteCount {
                details.append(KeepKeyValue("Response Size", ByteCountDisplay.string(responseSize)))
            }
            addSection(title: "Timing and Client", views: [KeyValueListView(rows: details)])

            if let error = transaction.errorDescription {
                let label = UILabel()
                label.text = error
                label.font = .preferredFont(forTextStyle: .subheadline)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .systemRed
                label.numberOfLines = 0
                addSection(title: "Error", views: [label])
            }
        }

        private func buildRequestResponse(headers: [String: String], body: KeepBody?, title: String) {
            let headersView = HeaderDisclosureView(headers: headers)
            addSection(title: "Headers", views: [headersView])

            guard let body else {
                addNoBodyMessage()
                return
            }

            addBodyCodeBlock(body, headers: headers, title: title)
            if body.isTruncated {
                addTruncatedBodyNote(byteCount: body.byteCount)
            }
        }

        private func addBodyCodeBlock(_ body: KeepBody, headers: [String: String], title: String) {
            let hasJSONContentType = headers.contains { pair in
                pair.key.lowercased() == "content-type" && pair.value.lowercased().contains("json")
            }
            if body.text.utf8.count >= CodeBlockView.formattingThreshold {
                let embedded = JSONFormatter.embeddedCandidate(body.text)
                let startsWithJSON = body.text.first(where: { !$0.isWhitespace })
                    .map { $0 == "{" || $0 == "[" } ?? false
                if let embedded {
                    addCodeBlock(
                        title: "\(title) Body",
                        text: embedded.json,
                        rawText: body.text,
                        isJSON: true,
                        byteCount: body.byteCount,
                        prefix: embedded.prefix
                    )
                } else {
                    addCodeBlock(
                        title: "\(title) Body",
                        text: body.text,
                        rawText: body.text,
                        isJSON: hasJSONContentType || startsWithJSON,
                        byteCount: body.byteCount
                    )
                }
            } else if let embedded = JSONFormatter.splitEmbedded(body.text) {
                addCodeBlock(
                    title: "\(title) Body",
                    text: embedded.json,
                    rawText: body.text,
                    isJSON: true,
                    byteCount: body.byteCount,
                    prefix: embedded.prefix
                )
            } else {
                let isJSON = hasJSONContentType || JSONFormatter.format(body.text) != nil
                addCodeBlock(
                    title: "\(title) Body",
                    text: body.text,
                    rawText: body.text,
                    isJSON: isJSON,
                    byteCount: body.byteCount
                )
            }
        }

        private func addNoBodyMessage() {
            let empty = UILabel()
            empty.text = "No body"
            empty.font = .preferredFont(forTextStyle: .subheadline)
            empty.textColor = .secondaryLabel
            addSection(title: "Body", views: [empty])
        }

        private func addTruncatedBodyNote(byteCount: Int) {
            let note = UILabel()
            note.text = "Truncated · total size \(ByteCountDisplay.string(byteCount))"
            note.font = .preferredFont(forTextStyle: .caption1)
            note.textColor = .secondaryLabel
            addSection(title: "Body Status", views: [note])
        }

        private func overviewText() -> String {
            var lines = [
                "Method:    \(transaction.method)",
                "URL:       \(transaction.url)",
                "Status:    \(transaction.statusCode.map(String.init) ?? "none")",
                "Duration:  \(Int(transaction.duration * 1000)) ms",
                "Started:   \(KeepCodec.displayString(for: transaction.startedAt))",
                "Client:    \(transaction.label)"
            ]
            if let error = transaction.errorDescription {
                lines.append("Error:     \(error)")
            }
            return lines.joined(separator: "\n")
        }

        private static func describe(headers: [String: String], body: KeepBody?) -> String {
            var lines = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            if lines.isEmpty {
                lines.append("(no headers)")
            }
            lines.append("")
            guard let body else {
                lines.append("(no body)")
                return lines.joined(separator: "\n")
            }
            lines.append("BODY (\(body.byteCount) bytes\(body.isTruncated ? ", truncated" : ""))")
            lines.append(body.text)
            return lines.joined(separator: "\n")
        }
    }

    private final class HeaderDisclosureView: UIView {
        private let button = UIButton(type: .system)
        private let valuesView: KeyValueListView
        private var isExpanded = false

        init(headers: [String: String]) {
            valuesView = KeyValueListView(rows: headers.keys.sorted().map { KeepKeyValue($0, headers[$0] ?? "") })
            super.init(frame: .zero)

            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
            button.setTitle("\(headers.count) headers", for: .normal)
            button.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            button.tintColor = .secondaryLabel
            button.semanticContentAttribute = .forceRightToLeft
            button.addTarget(self, action: #selector(toggle), for: .touchUpInside)

            let stack = UIStackView(arrangedSubviews: [button, valuesView])
            stack.axis = .vertical
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            valuesView.isHidden = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        @objc private func toggle() {
            isExpanded.toggle()
            valuesView.isHidden = !isExpanded
            button.setImage(UIImage(systemName: isExpanded ? "chevron.down" : "chevron.right"), for: .normal)
        }
    }
#endif
