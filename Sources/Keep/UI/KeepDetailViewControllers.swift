#if canImport(UIKit)
    import UIKit

    /// A monospaced, selectable text screen with Copy and Share. Used for log and network details.
    class KeepTextViewController: UIViewController, ToastPresentable {
        let textView = UITextView()
        let text: String
        let shareFileName: String?

        init(title: String, text: String, shareFileName: String? = nil) {
            self.text = text
            self.shareFileName = shareFileName
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
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.alwaysBounceVertical = true
            textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
            textView.text = text
            view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped)),
                UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyTapped))
            ]
        }

        @objc private func copyTapped() {
            copyToPasteboard(text) { [weak self] in
                self?.showPopup(message: "Copied to clipboard")
            }
        }

        @objc private func shareTapped() {
            let items: [Any]
            if let shareFileName, let url = try? writeTemporaryFile(named: shareFileName) {
                items = [url]
            } else {
                items = [text]
            }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
            present(activity, animated: true)
        }

        private func writeTemporaryFile(named name: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    final class LogDetailViewController: KeepTextViewController {
        init(entry: LogEntry) {
            super.init(title: "Log", text: Self.describe(entry))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
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

    final class NetworkDetailViewController: UIViewController {
        private let transaction: KeepHTTPTransaction
        private let segments = UISegmentedControl(items: ["Overview", "Request", "Response"])
        private let textView = UITextView()

        init(transaction: KeepHTTPTransaction) {
            self.transaction = transaction
            super.init(nibName: nil, bundle: nil)
            title = "\(transaction.method) \(transaction.statusCode.map(String.init) ?? "ERR")"
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            segments.selectedSegmentIndex = 0
            segments.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
            navigationItem.titleView = segments
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareHAR)),
                UIBarButtonItem(title: "cURL", style: .plain, target: self, action: #selector(copyCurl))
            ]

            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.alwaysBounceVertical = true
            textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
            view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            showSegment()
        }

        @objc private func segmentChanged() {
            showSegment()
        }

        private func showSegment() {
            switch segments.selectedSegmentIndex {
            case 1: textView.text = Self.describe(headers: transaction.requestHeaders, body: transaction.requestBody)
            case 2: textView.text = Self.describe(headers: transaction.responseHeaders, body: transaction.responseBody)
            default: textView.text = overview()
            }
        }

        private func overview() -> String {
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

        @objc private func copyCurl() {
            copyToPasteboard(transaction.curlCommand) { [weak self] in
                self?.showPopup(message: "cURL copied")
            }
        }

        @objc private func shareHAR() {
            do {
                let data = try HAR.data(for: [transaction], creatorVersion: KeepInfo.version)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("keep-request-\(transaction.id.prefix(8)).har")
                try data.write(to: url)
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
                present(activity, animated: true)
            } catch {
                showPopup(message: "Could not create HAR file")
            }
        }
    }

    extension NetworkDetailViewController: ToastPresentable {}
#endif
