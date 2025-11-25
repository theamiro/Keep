import Foundation
import Logging
import Testing
@testable import Keep

@Test
func cacheLoggingSourceStoresFetchesAndFlushes() async throws {
    let source = CacheLoggingSource()
    let log1 = Log(level: .info, description: "First log", timestamp: Date())
    let log2 = Log(level: .error, description: "Second log", timestamp: Date().addingTimeInterval(1))

    source.store(log1)
    source.store(log2)

    let fetched = source.fetch()
    #expect(fetched.count == 2)
    let identifiers = Set(fetched.map(\.id))
    #expect(identifiers.contains(log1.id))
    #expect(identifiers.contains(log2.id))

    source.flush {}
    #expect(source.fetch().isEmpty)
}

@Test
@MainActor
func inMemoryLoggingSourceStoresFetchesAndFlushes() async throws {
    let source = InMemoryLoggingSource.shared
    source.flush {}

    let log1 = Log(level: .info, description: "First in-memory log", timestamp: Date())
    let log2 = Log(level: .error, description: "Second in-memory log", timestamp: Date().addingTimeInterval(5))

    source.store(log1)
    source.store(log2)

    let fetched = source.fetch()
    #expect(fetched.count == 2)
    #expect(fetched.first?.id == log2.id)
    #expect(fetched.last?.id == log1.id)

    source.flush {}
    #expect(source.fetch().isEmpty)
}

@Test
@MainActor
func inMemoryLoggingSourceUpdateAndDelete() async throws {
    let source = InMemoryLoggingSource.shared
    source.flush {}

    var log = Log(level: .debug, description: "Original", timestamp: Date().addingTimeInterval(-10))
    source.store(log)

    log.pinned = true
    source.update(log: log)

    let fetchedAfterUpdate = source.fetch()
    #expect(fetchedAfterUpdate.count == 1)
    #expect(fetchedAfterUpdate.first?.pinned == true)

    source.deleteLog(withID: log.id)
    #expect(source.fetch().isEmpty)
}

@Test
@MainActor
func inMemoryLoggingSourceSharesStateBetweenHandlerAndViewModel() async throws {
    let configuration = KeepConfiguration(logHandler: .inMemoryCache, logLevel: .info)
    let source = InMemoryLoggingSource.shared
    source.flush {}

    let handler = KeepLogHandler(configuration: configuration)
    handler.log(
        level: .error,
        message: Logger.Message("Shared in-memory log"),
        metadata: ["domain": "tests"],
        source: "Tests",
        file: #fileID,
        function: #function,
        line: #line
    )

    let viewModel = FileLogViewModel(configuration: configuration)

    #expect(viewModel.logs.count == 1)
    #expect(viewModel.logs.first?.description == "Shared in-memory log")
    #expect(viewModel.logs.first?.metadata?["domain"] == .string("tests"))

    await viewModel.togglePin(for: viewModel.logs[0].id)
    #expect(InMemoryLoggingSource.shared.fetch().first?.pinned == true)

    source.flush {}
}

@Test
@MainActor
func inMemoryCacheLoggingDoesNotCreateDiskFiles() async throws {
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)

    let existingJSONFiles = Set(
        (try? fileManager.contentsOfDirectory(atPath: documentsURL.path)
            .filter { $0.hasSuffix(".json") }) ?? []
    )

    let configuration = KeepConfiguration(logHandler: .inMemoryCache, logLevel: .debug)
    let handler = KeepLogHandler(configuration: configuration)
    let source = InMemoryLoggingSource.shared
    source.flush {}

    handler.log(
        level: .error,
        message: Logger.Message("Diskless entry"),
        metadata: ["scenario": "in-memory"],
        source: "Tests",
        file: #fileID,
        function: #function,
        line: #line
    )

    #expect(!source.fetch().isEmpty)

    let jsonFilesAfterLog = Set(
        (try? fileManager.contentsOfDirectory(atPath: documentsURL.path)
            .filter { $0.hasSuffix(".json") }) ?? []
    )
    let newlyCreatedJSON = jsonFilesAfterLog.subtracting(existingJSONFiles)
    newlyCreatedJSON.forEach { newFile in
        try? fileManager.removeItem(at: documentsURL.appendingPathComponent(newFile))
    }

    #expect(
        newlyCreatedJSON.isEmpty,
        "In-memory logging should not create JSON files on disk"
    )

    source.flush {}
}

@Test
@MainActor
func inMemoryCacheClearsLogsAfterFlush() async throws {
    let configuration = KeepConfiguration(logHandler: .inMemoryCache, logLevel: .info)
    let handler = KeepLogHandler(configuration: configuration)
    let source = InMemoryLoggingSource.shared
    source.flush {}

    handler.log(
        level: .debug,
        message: Logger.Message("Session scoped log"),
        metadata: nil,
        source: "Tests",
        file: #fileID,
        function: #function,
        line: #line
    )

    var viewModel = FileLogViewModel(configuration: configuration)
    #expect(viewModel.logs.count == 1)

    source.flush {}

    viewModel = FileLogViewModel(configuration: configuration)
    #expect(
        viewModel.logs.isEmpty,
        "Flushing the in-memory cache should simulate closing the app and drop logs"
    )
}

@Test
func cacheLoggingSourceUpdateAndDelete() async throws {
    let source = CacheLoggingSource()
    var log = Log(level: .info, description: "Initial", timestamp: Date())
    source.store(log)

    // update pinned state
    log.pinned = true
    source.update(log: log)

    let fetchedAfterUpdate = source.fetch()
    #expect(fetchedAfterUpdate.count == 1)
    #expect(fetchedAfterUpdate.first?.pinned == true)

    source.deleteLog(withID: log.id)
    #expect(source.fetch().isEmpty)
}

@Test
@MainActor
func fileLoggingSourcePersistsFetchesAndClears() async throws {
    let fileName = "test-log-\(UUID().uuidString).json"
    let source = FileLoggingSource(fileName: fileName)

    defer {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: documentsURL.appendingPathComponent(fileName))
    }

    let olderDate = Date().addingTimeInterval(-60)
    let newerDate = Date()
    let olderLog = Log(level: .info, description: "Older", timestamp: olderDate)
    let newerLog = Log(level: .debug, description: "Newer", timestamp: newerDate)

    source.store(olderLog)
    source.store(newerLog)

    let fetched = source.fetch()
    #expect(fetched.count == 2)
    #expect(fetched.first?.id == newerLog.id)
    #expect(fetched.last?.id == olderLog.id)

    source.flush {}
    #expect(source.fetch().isEmpty)
}

@Test
@MainActor
func fileLoggingSourceUpdatePinsAndDeletes() async throws {
    let fileName = "handler-logs-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)
    let source = FileLoggingSource(fileName: fileName)

    defer { try? FileManager.default.removeItem(at: fileURL) }

    let baseDate = Date()
    let olderLog = Log(level: .debug, description: "Older", timestamp: baseDate.addingTimeInterval(-120))
    let newerLog = Log(level: .info, description: "Newer", timestamp: baseDate)

    source.store(olderLog)
    source.store(newerLog)

    var fetched = source.fetch()
    #expect(fetched.first?.id == newerLog.id)

    var pinnedOlder = olderLog
    pinnedOlder.pinned = true
    source.update(log: pinnedOlder)

    fetched = source.fetch()
    #expect(fetched.count == 2)
    #expect(fetched.first?.id == olderLog.id)
    #expect(fetched.first?.pinned == true)
    #expect(fetched.last?.id == newerLog.id)

    source.deleteLog(withID: olderLog.id)
    fetched = source.fetch()
    #expect(fetched.count == 1)
    #expect(fetched.first?.id == newerLog.id)
}
