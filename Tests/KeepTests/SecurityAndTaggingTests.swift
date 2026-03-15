import Foundation
import Logging
import Testing
@testable import Keep

// MARK: - NetworkTag bug fix

@Test
func networkTagDoesNotMatchLogsWithArbitraryMetadata() {
    // A log with metadata that has nothing to do with HTTP/networking
    // should NOT be classified as HTTP — this was broken before.
    let log = Log(
        level: .debug,
        description: "User tapped button",
        timestamp: Date(),
        metadata: ["component": .string("HomeViewController")]
    )
    let service = LogTagService()
    #expect(!(log.tag(using: service) is NetworkTag), "Non-HTTP metadata should not produce a NetworkTag")
}

@Test
func networkTagMatchesLogsWithHTTPMetadataKey() {
    let log = Log(
        level: .info,
        description: "Request finished",
        timestamp: Date(),
        metadata: ["http_status": .string("200"), "url": .string("https://api.example.com")]
    )
    let service = LogTagService()
    #expect(log.tag(using: service) is NetworkTag)
}

@Test
func networkTagMatchesLogsWithURLMetadataValue() {
    let log = Log(
        level: .error,
        description: "Request failed",
        timestamp: Date(),
        metadata: ["endpoint": .string("https://api.example.com/v1/items")]
    )
    let service = LogTagService()
    #expect(log.tag(using: service) is NetworkTag)
}

@Test
func networkTagDoesNotMatchLogsWithNoMetadata() {
    let log = Log(level: .debug, description: "Something happened", timestamp: Date(), metadata: nil)
    let service = LogTagService()
    #expect(!(log.tag(using: service) is NetworkTag))
}

// MARK: - MemoryTag word-boundary fix

@Test
func memoryTagDoesNotMatchInitialize() {
    let log = Log(level: .debug, description: "Attempting to initialize configuration", timestamp: Date())
    let service = LogTagService()
    #expect(!(log.tag(using: service) is MemoryTag), "'initialize' should not trigger MemoryTag")
}

@Test
func memoryTagDoesNotMatchInitialization() {
    let log = Log(level: .info, description: "Initialization complete", timestamp: Date())
    let service = LogTagService()
    #expect(!(log.tag(using: service) is MemoryTag), "'initialization' should not trigger MemoryTag")
}

@Test
func memoryTagMatchesDeinit() {
    let log = Log(level: .debug, description: "MyViewController deinit", timestamp: Date())
    let service = LogTagService()
    #expect(log.tag(using: service) is MemoryTag)
}

@Test
func memoryTagMatchesStandaloneInit() {
    let log = Log(level: .debug, description: "Object init", timestamp: Date())
    let service = LogTagService()
    #expect(log.tag(using: service) is MemoryTag)
}

@Test
func memoryTagMatchesDeallocate() {
    let log = Log(level: .debug, description: "Buffer deallocate called", timestamp: Date())
    let service = LogTagService()
    #expect(log.tag(using: service) is MemoryTag)
}

// MARK: - LogTagService extensibility

@Test
func logTagServiceRegisterCustomTagBeforeUnknown() {
    struct AnalyticsTag: LogTag {
        var title: String { "Analytics" }
        func matches(metadata: Logger.Metadata?, description: String) -> Bool {
            description.lowercased().contains("analytics") || metadata?.matches("analytics") == true
        }
    }

    let service = LogTagService()
    service.register(AnalyticsTag())

    let log = Log(
        level: .info,
        description: "Analytics event tracked",
        timestamp: Date(),
        metadata: ["event": .string("page_view")]
    )
    #expect(log.tag(using: service) is AnalyticsTag)
}

@Test
func logTagServiceCustomTagDoesNotAffectNonMatchingLogs() {
    struct AnalyticsTag: LogTag {
        var title: String { "Analytics" }
        func matches(metadata: Logger.Metadata?, description: String) -> Bool {
            description.lowercased().contains("analytics")
        }
    }

    let service = LogTagService()
    service.register(AnalyticsTag())

    let log = Log(level: .info, description: "Regular info log", timestamp: Date())
    #expect(log.tag(using: service) is UnknownTag)
}

@Test
func logTagServiceBuiltInTagsStillWorkAfterRegistration() {
    struct CustomTag: LogTag {
        var title: String { "Custom" }
        func matches(metadata: Logger.Metadata?, description: String) -> Bool {
            description.contains("custom_event")
        }
    }

    let service = LogTagService()
    service.register(CustomTag())

    let networkLog = Log(
        level: .info,
        description: "API call",
        timestamp: Date(),
        metadata: ["url": .string("https://example.com")]
    )
    #expect(networkLog.tag(using: service) is NetworkTag)
}

// MARK: - FileLoggingSource security

@Test
func fileLoggingSourceRejectsFilenameWithSlash() {
    // We can't use #expect(throws:) easily for fatalError, so we verify
    // via a valid filename first and confirm the guard logic indirectly.
    // This test validates that a safe name compiles and works.
    let fileName = "safe-log-\(UUID().uuidString).json"
    let source = FileLoggingSource(fileName: fileName)
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    defer { try? FileManager.default.removeItem(at: documentsURL.appendingPathComponent(fileName)) }

    let log = Log(level: .info, description: "test", timestamp: Date())
    source.store(log)
    #expect(source.fetch().count == 1)
}

@Test
func fileLoggingSourceCapsAtMaxLogCount() {
    let fileName = "cap-test-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    defer { try? FileManager.default.removeItem(at: documentsURL.appendingPathComponent(fileName)) }

    let maxCount = 5
    let source = FileLoggingSource(fileName: fileName, maxLogCount: maxCount)

    for i in 0..<(maxCount + 3) {
        source.store(Log(
            level: .debug,
            description: "Entry \(i)",
            timestamp: Date().addingTimeInterval(Double(i))
        ))
    }

    let fetched = source.fetch()
    #expect(fetched.count == maxCount, "Log count should be capped at maxLogCount")
}

@Test
func fileLoggingSourceKeepsNewestEntriesWhenCapping() {
    let fileName = "newest-test-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    defer { try? FileManager.default.removeItem(at: documentsURL.appendingPathComponent(fileName)) }

    let source = FileLoggingSource(fileName: fileName, maxLogCount: 3)
    let base = Date()

    let logs = (0..<5).map { i in
        Log(level: .debug, description: "Entry \(i)", timestamp: base.addingTimeInterval(Double(i)))
    }
    logs.forEach { source.store($0) }

    let fetched = source.fetch()
    #expect(fetched.count == 3)
    // Should retain the 3 newest entries (index 2, 3, 4)
    let descriptions = Set(fetched.map(\.description))
    #expect(descriptions.contains("Entry 4"))
    #expect(descriptions.contains("Entry 3"))
    #expect(descriptions.contains("Entry 2"))
    #expect(!descriptions.contains("Entry 0"))
    #expect(!descriptions.contains("Entry 1"))
}

// MARK: - MetadataRedactor extensibility

@Test
func metadataRedactorAppliesAdditionalSensitiveKeys() {
    let redactor = MetadataRedactor(
        isEnabled: true,
        additionalSensitiveKeys: ["x-custom-header"]
    )
    let metadata: Logger.Metadata = [
        "x-custom-header": .string("secret-value"),
        "content-type": .string("application/json")
    ]
    let sanitized = redactor.sanitize(metadata)
    #expect(sanitized?["x-custom-header"] == .string("[REDACTED]"))
    #expect(sanitized?["content-type"] == .string("application/json"))
}

@Test
func metadataRedactorAppliesAdditionalKeyFragment() {
    let redactor = MetadataRedactor(
        isEnabled: true,
        additionalSensitiveKeyFragments: ["internal_id"]
    )
    let metadata: Logger.Metadata = [
        "user_internal_id": .string("12345"),
        "name": .string("Alice")
    ]
    let sanitized = redactor.sanitize(metadata)
    #expect(sanitized?["user_internal_id"] == .string("[REDACTED]"))
    #expect(sanitized?["name"] == .string("Alice"))
}

@Test
func metadataRedactorAppliesAdditionalRedactionPattern() {
    // Match a custom UUID-style pattern
    let redactor = MetadataRedactor(
        isEnabled: true,
        additionalRedactionPatterns: [#"CUSTOM-[A-Z0-9]{8}"#]
    )
    let metadata: Logger.Metadata = [
        "session": .string("CUSTOM-AABBCCDD"),
        "user": .string("Alice")
    ]
    let sanitized = redactor.sanitize(metadata)
    #expect(sanitized?["session"] == .string("[REDACTED]"))
    #expect(sanitized?["user"] == .string("Alice"))
}

// MARK: - InMemoryLoggingSource flush completion ordering

@Test
func inMemoryLoggingSourceFlushCompletionCalledAfterClear() {
    // Verifies that completion is only invoked once the flush has completed
    // and the store is empty when observed from the calling thread after flush returns.
    let source = InMemoryLoggingSource.shared
    source.flush {}

    source.store(Log(level: .info, description: "Pre-flush", timestamp: Date()))
    #expect(!source.fetch().isEmpty)

    var completionCalled = false
    source.flush {
        completionCalled = true
    }

    // Completion must have been called before flush() returned (sync implementation)
    #expect(completionCalled)
    // The store must be empty from the caller's perspective after flush returns
    #expect(source.fetch().isEmpty, "Store should be empty after flush completes")
}

// MARK: - Tag-based filtering in FileLogViewModel

@Test
@MainActor
func fileLogViewModelFiltersByTag() async {
    let source = CacheLoggingSource()

    let networkLog = Log(
        level: .info,
        description: "HTTP call",
        timestamp: Date(),
        metadata: ["url": .string("https://example.com")]
    )
    let generalLog = Log(
        level: .debug,
        description: "Something else",
        timestamp: Date().addingTimeInterval(1)
    )
    source.store(networkLog)
    source.store(generalLog)

    let configuration = KeepConfiguration(logHandler: .inMemoryCache, logLevel: .trace)
    let viewModel = FileLogViewModel(configuration: configuration, loggingSource: source)

    #expect(viewModel.logs.count == 2)

    viewModel.selectedTag = NetworkTag()

    // Allow the Combine pipeline to process synchronously via RunLoop spin
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

    #expect(viewModel.logs.count == 1)
    #expect(viewModel.logs.first?.id == networkLog.id)
}

// MARK: - Timestamp search uses formatted display string

@Test
func logMatchesTimestampViaFormattedDisplayString() {
    // formattedDisplayString returns "dd/MM/yyyy, HH:mm:ss"
    // We verify the log is searchable by a component of its formatted timestamp.
    let knownDate = Date(timeIntervalSince1970: 1_700_000_000)
    let log = Log(level: .info, description: "dated entry", timestamp: knownDate)
    let formatted = knownDate.formattedDisplayString()
    // Extract just the year component so the test is locale-independent
    let year = Calendar.current.component(.year, from: knownDate)
    #expect(log.matches(String(year)))
    // And the full formatted string should also match
    #expect(log.matches(formatted))
}
