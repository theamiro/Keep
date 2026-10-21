import CryptoKit
import Foundation
@testable import Keep
import Logging
import Testing

@Suite("Capture, tagging and lifecycle")
struct KeepCoreTests {
    @Test func messagesAreRedactedBeforeTheyAreStored() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        let logger = makeLogger(core)
        logger.info("login ok", metadata: ["token": "secret-value"])
        core.drainQueue()

        let entry = try #require(core.logs.snapshot().first)
        #expect(entry.message == "login ok")
        #expect(entry.metadata["token"] == .string("[REDACTED]"))
        #expect(entry.label == "tests")
        #expect(entry.level == .info)
    }

    @Test func reportNotesAreRedactedBeforeTheyAreWritten() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        makeLogger(core).info("ready")
        core.drainQueue()

        let input = try core.reportInput(
            for: .currentSession,
            note: "Login failed with token=abc123 for jane@example.com"
        )
        let text = ReportBuilder.reportText(input, logs: input.logs, transactions: input.transactions)
        #expect(!text.contains("abc123"))
        #expect(!text.contains("jane@example.com"))
        #expect(text.contains("Note: Login failed with token=[REDACTED] for [REDACTED]"))
    }

    @Test func minimumLevelDropsLowerEntries() throws {
        var configuration = makeConfiguration()
        configuration.minimumLevel = .warning
        let core = try makeCore(configuration, directory: makeTemporaryDirectory())
        let logger = makeLogger(core)
        logger.info("ignored")
        logger.error("kept")
        core.drainQueue()
        #expect(core.logs.snapshot().map(\.message) == ["kept"])
    }

    @Test func tagsOnlyUseRealSignals() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        let logger = makeLogger(core)
        logger.info("curl -X GET https://api.example.com")
        logger.info("Loaded", metadata: ["url": "https://api.example.com"])
        logger.debug("ViewController deinit")
        logger.info("Initial state loaded", metadata: ["status": "200"])
        core.drainQueue()

        let tags = Dictionary(uniqueKeysWithValues: core.logs.snapshot().map { ($0.message, $0.tag) })
        #expect(tags["curl -X GET https://api.example.com"] == "HTTP")
        #expect(tags["Loaded"] == "HTTP")
        #expect(tags["ViewController deinit"] == "Memory")
        #expect(tags["Initial state loaded"] == "Unknown")
    }

    @Test func pinnedEntriesSurviveEvictionAndTogglesReturnTheNewState() throws {
        var configuration = makeConfiguration()
        configuration.memoryCapacity = 3
        let core = try makeCore(configuration, directory: makeTemporaryDirectory())
        let logger = makeLogger(core)
        logger.info("m0")
        core.drainQueue()
        let pinnedID = try #require(core.logs.snapshot().first?.id)
        #expect(core.togglePin(id: pinnedID) == true)
        for index in 1 ... 4 {
            logger.info("m\(index)")
        }
        core.drainQueue()

        let messages = core.logs.snapshot().map(\.message)
        #expect(messages.contains("m0"))
        #expect(messages.count == 3)
        #expect(core.togglePin(id: pinnedID) == false)
        #expect(core.togglePin(id: "missing") == nil)
    }

    @Test func clearSessionEmptiesTheBuffers() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        makeLogger(core).info("something")
        core.drainQueue()
        core.clearSession()
        #expect(core.logs.snapshot().isEmpty)
    }

    @Test func disallowedDistributionStoresNothingAndDeletesLeftovers() throws {
        let directory = try makeTemporaryDirectory()
        try Data("old".utf8).write(to: directory.appendingPathComponent("crash-snapshot.bin"))
        let core = makeCore(makeConfiguration(.appStore), directory: directory)
        #expect(!core.isEnabled)
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        makeLogger(core).info("must not be stored")
        core.drainQueue()
        #expect(core.logs.snapshot().isEmpty)
    }

    @Test func allowedDistributionsRunKeep() throws {
        for distribution in [KeepDistribution.simulator, .development, .adHoc, .testFlight] {
            let core = try makeCore(makeConfiguration(distribution), directory: makeTemporaryDirectory())
            #expect(core.isEnabled, "\(distribution) should be allowed by default")
        }
    }

    @Test func crashSnapshotIsEncryptedAndOfferedOnceOnTheNextLaunch() throws {
        let directory = try makeTemporaryDirectory()
        let key = SymmetricKey(size: .bits256)
        let first = makeCore(directory: directory, key: key)
        makeLogger(first).info("checkout started for account 991")
        first.drainQueue()
        first.recordCrash(name: "NSRangeException", reason: "index 5 beyond bounds", callStack: ["frame0"])

        let snapshotURL = directory.appendingPathComponent("crash-snapshot.bin")
        let raw = try Data(contentsOf: snapshotURL)
        #expect(!String(decoding: raw, as: UTF8.self).contains("checkout started"))

        let second = makeCore(directory: directory, key: key)
        let crashed = try #require(second.previousSnapshot)
        #expect(crashed.logs.contains { $0.message == "Uncaught exception NSRangeException: index 5 beyond bounds" })
        #expect(crashed.logs.contains { $0.message == "checkout started for account 991" })
        #expect(!FileManager.default.fileExists(atPath: snapshotURL.path))

        let third = makeCore(directory: directory, key: key)
        #expect(third.previousSnapshot == nil)
    }

    @Test func noKeyMeansNoSnapshotFile() throws {
        let directory = try makeTemporaryDirectory()
        let core = makeCore(directory: directory, key: nil)
        core.recordCrash(name: "NSException", reason: "boom", callStack: [])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("crash-snapshot.bin").path))
    }

    @Test func distributionDetectorReadsGetTaskAllow() throws {
        let directory = try makeTemporaryDirectory()
        let development = directory.appendingPathComponent("dev.mobileprovision")
        try Data("<dict><key>get-task-allow</key>\n\t<true/>\n</dict>".utf8).write(to: development)
        let adHoc = directory.appendingPathComponent("adhoc.mobileprovision")
        try Data("<dict><key>get-task-allow</key>\n\t<false/>\n</dict>".utf8).write(to: adHoc)
        #expect(LiveDistributionDetector.isDevelopmentProfile(at: development))
        #expect(!LiveDistributionDetector.isDevelopmentProfile(at: adHoc))
    }
}
