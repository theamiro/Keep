import Foundation
import Testing
@testable import Keep

@Test
@MainActor
func fileLogViewModelLoadsAndClearsFileLogs() async throws {
    let fileName = "view-model-log-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)

    defer { try? FileManager.default.removeItem(at: fileURL) }

    let source = FileLoggingSource(fileName: fileName)
    let olderDate = Date().addingTimeInterval(-120)
    let newerDate = Date()
    let olderLog = Log(level: .info, description: "Older", timestamp: olderDate)
    let newerLog = Log(level: .notice, description: "Newer", timestamp: newerDate)

    source.store(olderLog)
    source.store(newerLog)

    let viewModel = FileLogViewModel(configuration: .init(logHandler: .fileSystem(fileName), logLevel: .debug))

    #expect(viewModel.logs.count == 2)
    #expect(viewModel.logs.first?.id == newerLog.id)
    #expect(viewModel.logs.last?.id == olderLog.id)

    await withCheckedContinuation { continuation in
        viewModel.clearLogs {
            continuation.resume()
        }
    }

    viewModel.fetchLogs()
    #expect(viewModel.logs.isEmpty)
}

@Test
@MainActor
func fileLogViewModelTogglePinPromotesLog() async throws {
    let fileName = "view-model-pin-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)

    defer { try? FileManager.default.removeItem(at: fileURL) }

    let source = FileLoggingSource(fileName: fileName)
    let baseDate = Date()
    let olderLog = Log(level: .debug, description: "Older", timestamp: baseDate.addingTimeInterval(-300))
    let newerLog = Log(level: .notice, description: "Newer", timestamp: baseDate)

    source.store(olderLog)
    source.store(newerLog)

    let viewModel = FileLogViewModel(configuration: .init(logHandler: .fileSystem(fileName), logLevel: .trace))

    #expect(viewModel.logs.first?.id == newerLog.id)

    await viewModel.togglePin(for: olderLog.id)

    #expect(viewModel.logs.first?.id == olderLog.id)
    #expect(viewModel.logs.first?.pinned == true)
}

@Test
@MainActor
func fileLogViewModelTogglePinAndUnpinRestoresOrdering() async throws {
    let fileName = "view-model-pin-cycle-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)

    defer { try? FileManager.default.removeItem(at: fileURL) }

    let source = FileLoggingSource(fileName: fileName)
    let baseDate = Date()
    let candidate = Log(level: .debug, description: "Toggle", timestamp: baseDate.addingTimeInterval(-60))
    let newest = Log(level: .info, description: "Newest", timestamp: baseDate)

    source.store(candidate)
    source.store(newest)

    let viewModel = FileLogViewModel(configuration: .init(logHandler: .fileSystem(fileName), logLevel: .trace))

    #expect(viewModel.logs.first?.id == newest.id)

    await viewModel.togglePin(for: candidate.id)

    #expect(viewModel.logs.first?.id == candidate.id)
    #expect(viewModel.logs.first?.pinned == true)

    await viewModel.togglePin(for: candidate.id)

    #expect(viewModel.logs.first?.id == newest.id)
    #expect(viewModel.logs.contains(where: { $0.id == candidate.id && $0.pinned == false }))
}

@Test
@MainActor
func fileLogViewModelDeleteRemovesLog() async throws {
    let fileName = "view-model-delete-\(UUID().uuidString).json"
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)

    defer { try? FileManager.default.removeItem(at: fileURL) }

    let source = FileLoggingSource(fileName: fileName)
    let logA = Log(level: .info, description: "A", timestamp: Date())
    let logB = Log(level: .error, description: "B", timestamp: Date().addingTimeInterval(10))

    source.store(logA)
    source.store(logB)

    let viewModel = FileLogViewModel(configuration: .init(logHandler: .fileSystem(fileName), logLevel: .trace))

    #expect(viewModel.logs.count == 2)

    await viewModel.deleteLog(withID: logA.id)

    #expect(viewModel.logs.count == 1)
    #expect(viewModel.logs.first?.id == logB.id)
}

@Test
func logSectionBuilderPlacesPinnedSectionFirst() {
    let baseDate = Date()
    let pinnedLog = Log(level: .notice, description: "Pinned", timestamp: baseDate, pinned: true)
    let anotherPinned = Log(level: .warning, description: "Pinned Too", timestamp: baseDate.addingTimeInterval(-5), pinned: true)
    let unpinnedLog = Log(level: .debug, description: "Unpinned", timestamp: baseDate.addingTimeInterval(-10))

    let sections = LogSectionBuilder.makeSections(from: [unpinnedLog, pinnedLog, anotherPinned])

    #expect(sections.count == 2)
    #expect(sections.first?.title == "Pinned")
    #expect(sections.first?.logs.allSatisfy { $0.pinned } == true)
    #expect(sections.last?.title == "All")
    #expect(sections.last?.logs.allSatisfy { !$0.pinned } == true)
}
