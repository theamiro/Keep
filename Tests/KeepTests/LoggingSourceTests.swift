import Foundation
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
