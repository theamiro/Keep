#if canImport(UIKit)
    import SwiftUI
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
            super.configureNavigationItems()
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

        override func detailActions() -> [KeepDetailAction] {
            let transaction = transaction
            return [
                KeepDetailAction(title: "Copy cURL", kind: .copy { [weak self] in self?.copyCurl() }),
                KeepDetailAction(title: "Copy all", kind: .copy { [weak self] in self?.copyAllToPasteboard() }),
                KeepDetailAction(
                    title: "Share HAR file",
                    kind: .shareFile(name: "keep-request-\(transaction.id.prefix(8)).har") {
                        try HAR.data(for: [transaction], creatorVersion: KeepInfo.version)
                    }
                ),
                KeepDetailAction(title: "Share cURL", kind: .shareText { transaction.curlCommand })
            ]
        }

        @objc private func segmentChanged() {
            renderSegment()
        }

        private func copyCurl() {
            copyToPasteboard(transaction.curlCommand) { [weak self] in
                self?.showPopup(message: "cURL copied")
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
            addSection(title: "Transaction") {
                TransactionSummary(transaction: transaction)
            }
            addCodeBlock(title: "URL", text: transaction.url, byteCount: transaction.url.utf8.count)

            if let components = URLComponents(string: transaction.url),
                let queryItems = components.queryItems,
                !queryItems.isEmpty
            {
                addSection(title: "Query Parameters") {
                    KeyValueList(rows: queryItems.map { KeepKeyValue($0.name, $0.value ?? "") })
                }
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
            addSection(title: "Timing and Client") {
                KeyValueList(rows: details)
            }

            if let error = transaction.errorDescription {
                addSection(title: "Error") {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }

        private func buildRequestResponse(headers: [String: String], body: KeepBody?, title: String) {
            addSection(title: "Headers") {
                HeadersDisclosure(headers: headers)
            }

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
                let startsWithJSON =
                    body.text.first(where: { !$0.isWhitespace })
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
            addSection(title: "Body") {
                KeepNote(text: "No body")
            }
        }

        private func addTruncatedBodyNote(byteCount: Int) {
            addSection(title: "Body Status") {
                KeepNote(text: "Truncated · total size \(ByteCountDisplay.string(byteCount))", font: .caption)
            }
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

    #if DEBUG
        @available(iOS 17, *)
        #Preview("Success") {
            UINavigationController(rootViewController: NetworkDetailViewController(transaction: PreviewSamples.success))
        }

        @available(iOS 17, *)
        #Preview("Failed") {
            UINavigationController(rootViewController: NetworkDetailViewController(transaction: PreviewSamples.failed))
        }
    #endif
#endif
