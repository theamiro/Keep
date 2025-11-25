import Foundation
import Logging
import Testing
@testable import Keep
#if canImport(AppKit)
import AppKit
#endif

@Test
func cacheExpiresEntriesBasedOnLifetime() {
    var now = Date()
    let cache = Cache<String, String>(dateProvider: { now }, lifetime: 1.0, maximumEntryCount: 4)

    cache.insert("alpha", forKey: "first")
    #expect(cache.value(forKey: "first") == "alpha")

    now = now.addingTimeInterval(2)
    #expect(cache.value(forKey: "first") == nil)
}

@Test
func cacheCodableRoundTripPreservesEntries() throws {
    let cache = Cache<String, String>()
    cache.insert("one", forKey: "1")
    cache.insert("two", forKey: "2")

    let encoded = try JSONEncoder().encode(cache)
    let decoded = try JSONDecoder().decode(Cache<String, String>.self, from: encoded)
    let values = decoded.allValues()

    #expect(values.contains("one"))
    #expect(values.contains("two"))
}

@Test
func logEncodingRedactsSensitiveMetadata() throws {
    let metadata: Logger.Metadata = [
        "headers": .dictionary([
            "Authorization": .string("Bearer 123"),
            "Content-Type": .string("application/json"),
            "customToken": .string("secret")
        ])
    ]
    let redactor = MetadataRedactor(isEnabled: true)
    let sanitizedMetadata = redactor.sanitize(metadata)
    let log = Log(
        level: .info,
        description: "Request finished",
        timestamp: Date(),
        metadata: sanitizedMetadata
    )

    let data = try JSONEncoder().encode(log)
    let decoded = try JSONDecoder().decode(Log.self, from: data)

    let headers = decoded.metadata?["headers"]
    guard case let .dictionary(values)? = headers else {
        Issue.record("Expected dictionary metadata")
        return
    }

    #expect(values["Authorization"] == .string("[REDACTED]"))
    #expect(values["customToken"] == .string("[REDACTED]"))
    #expect(values["Content-Type"] == .string("application/json"))
}

@Test
func logEncodingPreservesSensitiveMetadataWhenRedactionDisabled() throws {
    let metadata: Logger.Metadata = [
        "Authorization": .string("Bearer 123"),
        "customToken": .string("secret"),
        "Content-Type": .string("application/json")
    ]
    let redactor = MetadataRedactor(isEnabled: false)
    let sanitizedMetadata = redactor.sanitize(metadata)
    let log = Log(
        level: .info,
        description: "Request finished",
        timestamp: Date(),
        metadata: sanitizedMetadata
    )

    let data = try JSONEncoder().encode(log)
    let decoded = try JSONDecoder().decode(Log.self, from: data)

    #expect(decoded.metadata?["Authorization"] == .string("Bearer 123"))
    #expect(decoded.metadata?["customToken"] == .string("secret"))
    #expect(decoded.metadata?["Content-Type"] == .string("application/json"))
}

@Test
func logMatchesSearchTermIncludesMetadata() {
    let log = Log(
        level: .debug,
        description: "User signed in",
        timestamp: Date(),
        metadata: ["request-id": .string("ABC-123"), "path": .string("/login")],
        source: "auth"
    )

    #expect(log.matches("abc"))
    #expect(log.matches("/login"))
    #expect(log.matches("auth"))
    #expect(log.matches("signed"))
    #expect(log.matches(String(log.line)))
    #expect(log.matches(log.file.split(separator: ".").first.map(String.init) ?? ""))
}

@Test
@MainActor
func logTagDetectsNetworkAndMemory() {
    let networkLog = Log(
        level: .info,
        description: "GET /users",
        timestamp: Date(),
        metadata: ["url": .string("https://example.com")]
    )
    #expect(networkLog.tag is NetworkTag)

    let memoryLog = Log(level: .debug, description: "Controller deinit", timestamp: Date())
    #expect(memoryLog.tag is MemoryTag)

    let unknownLog = Log(level: .error, description: "Unhandled", timestamp: Date(), metadata: nil)
    #expect(unknownLog.tag is UnknownTag)
}

@Test
func fileLoggingSourceFetchReturnsSortedLogs() throws {
    let fileName = "handler-logs-\(UUID()).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let source = FileLoggingSource(fileName: fileName)

    let older = Log(level: .debug, description: "Older", timestamp: Date().addingTimeInterval(-10))
    let newer = Log(level: .debug, description: "Newer", timestamp: Date())

    source.store(older)
    source.store(newer)

    let fetched = source.fetch()
    #expect(fetched.count == 2)
    #expect(fetched.first?.id == newer.id)
    #expect(fetched.last?.id == older.id)
}

@Test
func keepLogHandlerPersistsLogsToFile() throws {
    let fileName = "keep-handler-\(UUID()).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let configuration = KeepConfiguration(logHandler: .fileSystem(fileName), logLevel: .debug)
    let handler = KeepLogHandler(configuration: configuration)
    handler[metadataKey: "environment"] = .string("tests")

    handler.log(
        level: .info,
        message: "Handled request",
        metadata: ["url": .string("https://example.com")],
        source: "tests",
        file: #fileID,
        function: #function,
        line: #line
    )

    let data = try Data(contentsOf: fileURL)
    let logs = try JSONDecoder().decode([Log].self, from: data)

    #expect(logs.count == 1)
    #expect(logs.first?.metadata?["environment"] == .string("tests"))
    #expect(logs.first?.metadata?["url"] == .string("https://example.com"))
}

@Test
func keepLogHandlerHonorsDisabledRedaction() throws {
    let fileName = "keep-handler-no-redaction-\(UUID()).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)
    defer {
        try? FileManager.default.removeItem(at: fileURL)
    }

    let configuration = KeepConfiguration(
        logHandler: .fileSystem(fileName),
        logLevel: .debug,
        redactsSensitiveInformation: false
    )
    let handler = KeepLogHandler(configuration: configuration)

    handler.log(
        level: .info,
        message: "Handled request",
        metadata: ["Authorization": .string("Bearer 123"), "customToken": .string("secret")],
        source: "tests",
        file: #fileID,
        function: #function,
        line: #line
    )

    let data = try Data(contentsOf: fileURL)
    let logs = try JSONDecoder().decode([Log].self, from: data)

    #expect(logs.count == 1)
    #expect(logs.first?.metadata?["Authorization"] == .string("Bearer 123"))
    #expect(logs.first?.metadata?["customToken"] == .string("secret"))
}

@Test
func generateSampleDataLoadsBundledResource() {
    let data = generateSampleData(for: "log")
    #expect(!data.isEmpty)
}

@Test
func intAbbreviatedProducesExpectedSuffixes() {
    #expect(999.abbreviated == "999")
    #expect(1_500.abbreviated == "1K")
    #expect(2_500_000.abbreviated == "2M")
    #expect(7_000_000_000.abbreviated == "7B")
    #expect(9_000_000_000_000.abbreviated == "9T")
}

@Test
func iso8601FormatterConsistency() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let expected = Formatter.iso8601.string(from: date)

    #expect(date.ISO8601Format() == expected)
    #expect(expected.iso8601Date != nil)
}

@Test
func formattedDateMatchesFormatterConfiguration() {
    let date = Date(timeIntervalSince1970: 1_700_123_456)
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM/yyyy, HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current

    #expect(date.formattedDisplayString() == formatter.string(from: date))
}

#if canImport(AppKit)
@Test
func copyToPasteboardWritesStringOnMac() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("stale", forType: .string)

    var completionCalled = false

    copyToPasteboard("fresh", completion: {
        completionCalled = true
    })

    #expect(pasteboard.string(forType: .string) == "fresh")
    #expect(completionCalled == true)
}
#endif
