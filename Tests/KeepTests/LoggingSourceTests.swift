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
