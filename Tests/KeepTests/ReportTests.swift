import Foundation
@testable import Keep
import Logging
import Testing

@Suite("Report archive")
struct ReportTests {
    /// Entries go through a real core, so the report sees exactly what the app would have stored.
    private func sampleInput() throws -> ReportInput {
        let core = try makeCore(directory: makeTemporaryDirectory())
        makeLogger(core, label: "auth").error(
            "Login failed for Bearer live-secret-7",
            metadata: ["token": "sk-token-value", "attempt": "2"]
        )
        core.drainQueue()
        return ReportInput(
            title: "Current session",
            logs: core.logs.snapshot(),
            transactions: [],
            device: makeDevice(),
            note: "Button does nothing",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    @Test func reportTextIncludesNoteAndRedactedEntries() throws {
        let input = try sampleInput()
        let text = ReportBuilder.reportText(input, logs: input.logs, transactions: [])
        #expect(text.contains("Note: Button does nothing"))
        #expect(text.contains("ERROR [auth] [Unknown]"))
        #expect(text.contains("attempt: 2"))
        #expect(text.contains("token: [REDACTED]"))
        #expect(!text.contains("sk-token-value"))
        #expect(!text.contains("live-secret-7"))
    }

    @Test func logsJSONLinesHaveOneObjectPerLine() throws {
        let data = try ReportBuilder.logsJSONL(sampleInput().logs)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 1)
        let decoded = try KeepCodec.decoder().decode(LogEntry.self, from: Data(lines[0].utf8))
        #expect(decoded.message.contains("[REDACTED]"))
    }

    @Test func archiveContainsTheFourFilesAndIsNamedFromTheApp() throws {
        #if os(macOS)
            let url = try ReportBuilder.archive(sampleInput())
            #expect(url.pathExtension == "zip")
            #expect(url.lastPathComponent.hasPrefix("Keep-Eazy-1.2(45)-"))

            let listing = try run(["/usr/bin/unzip", "-Z1", url.path])
            for name in ["report.txt", "logs.jsonl", "network.har", "device.json"] {
                #expect(listing.contains(name), "archive should contain \(name)")
            }
            let report = try run(["/usr/bin/unzip", "-p", url.path, "*/report.txt"])
            #expect(report.contains("Note: Button does nothing"))
            #expect(!report.contains("live-secret-7"))
        #endif
    }

    #if os(macOS)
        private func run(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = Array(arguments.dropFirst())
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
    #endif
}
