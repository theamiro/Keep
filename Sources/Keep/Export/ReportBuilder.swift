import Foundation

/// Everything a report contains, captured on the caller's side so the archive can be built off the main thread.
struct ReportInput: Sendable {
    let title: String
    let logs: [LogEntry]
    let transactions: [KeepHTTPTransaction]
    let device: DeviceContext
    let note: String?
    let generatedAt: Date
}

/// Builds the shareable report: a folder with report.txt, logs.jsonl, network.har and device.json, zipped.
enum ReportBuilder {
    static func archive(_ input: ReportInput) throws -> URL {
        let name = archiveName(for: input.device, at: input.generatedAt)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-\(UUID().uuidString)", isDirectory: true)
        let folder = workDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let logs = input.logs.sorted { $0.sequence < $1.sequence }
        let transactions = input.transactions.sorted { $0.startedAt < $1.startedAt }
        try reportText(input, logs: logs, transactions: transactions)
            .write(to: folder.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        try logsJSONL(logs).write(to: folder.appendingPathComponent("logs.jsonl"))
        try HAR.data(for: transactions, creatorVersion: KeepInfo.version)
            .write(to: folder.appendingPathComponent("network.har"))
        try KeepCodec.encoder(pretty: true).encode(input.device)
            .write(to: folder.appendingPathComponent("device.json"))
        return try zip(folder: folder, name: name, in: workDirectory)
    }

    static func archiveName(for device: DeviceContext, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let app = device.appName.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        return "Keep-\(String(app))-\(device.appVersion)(\(device.appBuild))-\(formatter.string(from: date))"
    }

    static func reportText(_ input: ReportInput, logs: [LogEntry], transactions: [KeepHTTPTransaction]) -> String {
        let device = input.device
        var lines = [
            "Keep report: \(input.title)",
            "Generated: \(KeepCodec.displayString(for: input.generatedAt))",
            "App: \(device.appName) \(device.appVersion) (\(device.appBuild)) \(device.bundleIdentifier)",
            "Distribution: \(device.distribution)",
            "Device: \(device.deviceModel), \(device.operatingSystem)",
            "Locale: \(device.locale), time zone \(device.timeZone)",
            "Session started: \(KeepCodec.displayString(for: device.sessionStartedAt))"
        ]
        if let user = device.userIdentifier {
            lines.append("User: \(user)")
        }
        lines.append("Note: \(input.note.flatMap { $0.isEmpty ? nil : $0 } ?? "-")")
        lines.append("Entries: \(logs.count) log, \(transactions.count) network")
        lines.append("")
        lines.append("== Logs (oldest first)")
        for entry in logs {
            lines.append(
                "\(KeepCodec.displayString(for: entry.timestamp)) \(entry.level.rawValue.uppercased()) "
                    + "[\(entry.label)] [\(entry.tag)] \(entry.message)"
            )
            for key in entry.metadata.keys.sorted() {
                lines.append("    \(key): \(entry.metadata[key]?.text ?? "")")
            }
            lines.append("    at \(entry.file):\(entry.line) \(entry.function)")
        }
        lines.append("")
        lines.append("== Network (oldest first)")
        for transaction in transactions {
            let status = transaction.statusCode.map(String.init) ?? "ERR"
            let milliseconds = Int(transaction.duration * 1000)
            lines.append(
                "\(KeepCodec.displayString(for: transaction.startedAt)) \(transaction.method) \(status) "
                    + "\(milliseconds) ms [\(transaction.label)] \(transaction.url)"
            )
            if let error = transaction.errorDescription {
                lines.append("    error: \(error)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func logsJSONL(_ logs: [LogEntry]) throws -> Data {
        let encoder = KeepCodec.encoder()
        var data = Data()
        for entry in logs {
            try data.append(encoder.encode(entry))
            data.append(0x0A)
        }
        return data
    }

    /// Uses NSFileCoordinator's ".forUploading" option, which zips a folder without a third-party dependency.
    private static func zip(folder: URL, name: String, in directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent("\(name).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) {
            zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            throw error
        }
        return destination
    }
}
