import Foundation
import Logging
import Testing

@testable import Keep

@Suite("Memory limits")
struct MemoryLimitTests {
    private func makeTransaction(index: Int) throws -> KeepHTTPTransaction {
        let url = try #require(URL(string: "https://api.example.com/items/\(index)"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return KeepHTTPTransaction(
            label: "URLSession",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            duration: 0.1,
            request: URLRequest(url: url),
            response: response,
            // Spaces have no words for the redaction patterns to match, so this stays quick to redact.
            responseBody: Data(repeating: 0x20, count: 200_000)
        )
    }

    @Test func byteBudgetEvictsTheOldestUntilTheKeptCostFits() {
        let buffer = MemoryBuffer<Int>(capacity: 100, order: { $0 < $1 }, byteBudget: 10, cost: { $0 })
        buffer.append(4)
        buffer.append(4)
        buffer.append(4)
        #expect(buffer.snapshot() == [4, 4])
    }

    @Test func theNewestElementIsKeptEvenWhenItAloneExceedsTheBudget() {
        let buffer = MemoryBuffer<Int>(capacity: 100, order: { $0 < $1 }, byteBudget: 10, cost: { $0 })
        buffer.append(3)
        buffer.append(50)
        #expect(buffer.snapshot() == [50])
    }

    @Test func modifyingAnElementChangesWhatItCosts() {
        let buffer = MemoryBuffer<Int>(capacity: 100, order: { $0 < $1 }, byteBudget: 10, cost: { $0 })
        buffer.append(5)
        buffer.modify(where: { $0 == 5 }, { $0 = 9 })
        buffer.append(4)
        #expect(buffer.snapshot() == [4])
    }

    @Test func networkTransactionsAreEvictedByBytes() throws {
        var configuration = makeConfiguration()
        configuration.networkByteBudget = 1_000_000
        let core = makeCore(configuration, directory: try makeTemporaryDirectory())
        for index in 0..<6 {
            core.record(try makeTransaction(index: index))
        }
        core.drainQueue()
        // Each transaction is about 200 KB, so four fit under 1 MB.
        #expect(core.transactions.snapshot().count == 4)
    }

    @Test func longLogMessagesAreCutAndMarked() throws {
        let core = makeCore(directory: try makeTemporaryDirectory())
        let logger = makeLogger(core)
        // Words, not one long run: redaction is quadratic in the length of a run of letters and digits until the
        // bounded email pattern (PR #30) is in. Words keep this test about the cap alone.
        let long = String(repeating: "word ", count: 40_000)
        logger.info("\(long)")
        core.drainQueue()

        let entry = try #require(core.logs.snapshot().first)
        #expect(entry.message.utf8.count < KeepCore.maximumLogTextBytes + 64)
        #expect(entry.message.hasSuffix("200000 bytes]"))
    }

    @Test func longMetadataStringsAreCutToo() throws {
        let core = makeCore(directory: try makeTemporaryDirectory())
        let logger = makeLogger(core)
        logger.info("body", metadata: ["payload": .string(String(repeating: "word ", count: 20_000))])
        core.drainQueue()

        let entry = try #require(core.logs.snapshot().first)
        guard case .string(let payload)? = entry.metadata["payload"] else {
            Issue.record("payload metadata is missing or not a string")
            return
        }
        #expect(payload.utf8.count < KeepCore.maximumLogTextBytes + 64)
    }

    @Test func staleKeepEntriesInTheTemporaryDirectoryAreRemoved() throws {
        let directory = try makeTemporaryDirectory()
        let fileManager = FileManager.default
        let staleFolder = directory.appendingPathComponent("keep-old-report", isDirectory: true)
        try fileManager.createDirectory(at: staleFolder, withIntermediateDirectories: true)
        let staleFile = directory.appendingPathComponent("keep-log-1.txt")
        try Data("old".utf8).write(to: staleFile)
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)

        KeepCore.removeStaleTemporaryFiles(in: directory)

        #expect(!fileManager.fileExists(atPath: staleFolder.path))
        #expect(!fileManager.fileExists(atPath: staleFile.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }

    @Test func deeplyNestedJSONIsNotFormattedAndDoesNotCrash() {
        let deep = String(repeating: "[", count: 300) + String(repeating: "]", count: 300)
        #expect(JSONFormatter.format(deep) == nil)
        let nested = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)
        #expect(JSONFormatter.format(nested) != nil)
    }

    @Test func embeddedJSONSearchTriesOnlyTheFirstSixteenBrackets() {
        let noise = String(repeating: "[ ", count: 20)
        #expect(JSONFormatter.splitEmbedded(noise + #"{"a":1}"#) == nil)
        #expect(JSONFormatter.splitEmbedded("status " + #"{"a":1}"#) != nil)
    }
}
