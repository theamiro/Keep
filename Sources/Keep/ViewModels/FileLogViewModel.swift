//
//  FileLogViewModel.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import Foundation
import Logging
import Combine

@MainActor
public final class FileLogViewModel: ObservableObject {
    private let loggingSource: LoggingSource
    private let configuration: KeepConfiguration

    @Published var searchTerm: String = ""
    @Published var selectedLevel: Logging.Logger.Level?

    @Published private(set) var logs: [Log] = []
    private var allLogs: [Log] = []

    private var cancellables = Set<AnyCancellable>()

    static var preview: FileLogViewModel {
        let sampleLogs = makePreviewLogs()
        let previewSource = CacheLoggingSource()
        sampleLogs.forEach { previewSource.store($0) }
        return FileLogViewModel(
            configuration: .init(logHandler: .inMemoryCache, logLevel: .trace),
            loggingSource: previewSource
        )
    }

    public convenience init(configuration: KeepConfiguration) {
        self.init(
            configuration: configuration,
            loggingSource: FileLogViewModel.makeLoggingSource(for: configuration)
        )
    }

    internal init(configuration: KeepConfiguration, loggingSource: LoggingSource) {
        self.configuration = configuration
        self.loggingSource = loggingSource
        fetchLogs()
        configureObservation()
    }

    private func configureObservation() {
        $searchTerm
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.filterLogs()
            }
            .store(in: &cancellables)
        $selectedLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.filterLogs()
            }
            .store(in: &cancellables)
    }

    func fetchLogs() {
        let fetchedLogs = loggingSource.fetch()
        allLogs = sortLogs(fetchedLogs)
        filterLogs()
    }

    func clearLogs(completion: @escaping () -> Void) {
        loggingSource.flush {
            completion()
        }
    }

    func togglePin(for logID: String) async {
        guard let existingLogIndex = allLogs.firstIndex(where: { $0.id == logID }) else {
            return
        }
        var updatedLog = allLogs[existingLogIndex]
        updatedLog.pinned.toggle()
        loggingSource.update(log: updatedLog)
        let refreshedLogs = loggingSource.fetch()
        allLogs = sortLogs(refreshedLogs)
        filterLogs()
    }

    func deleteLog(withID logID: String) async {
        loggingSource.deleteLog(withID: logID)
        let refreshedLogs = loggingSource.fetch()
        allLogs = sortLogs(refreshedLogs)
        filterLogs()
    }

    private func filterLogs() {
        let filtered = allLogs.filter { log in
            let matchesSearch = searchTerm.isEmpty || log.matches(searchTerm)
            let matchesLevel = selectedLevel == nil || log.level == selectedLevel
            return matchesSearch && matchesLevel
        }
        logs = sortLogs(filtered)
    }

    private func sortLogs(_ logs: [Log]) -> [Log] {
        logs.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            return lhs.timestamp > rhs.timestamp
        }
    }
}

private extension FileLogViewModel {
    static func makeLoggingSource(for configuration: KeepConfiguration) -> LoggingSource {
        switch configuration.logHandler {
        case .fileSystem(let fileName):
            return FileLoggingSource(fileName: fileName)
        case .inMemoryCache:
            return CacheLoggingSource()
        }
    }

    static func makePreviewLogs() -> [Log] {
        let data = generateSampleData(for: "log")
        if let decoded = try? JSONDecoder().decode([Log].self, from: data), !decoded.isEmpty {
            var enrichedLogs = decoded

            let criticalIndices = enrichedLogs.enumerated()
                .filter { _, log in log.level == .critical || log.level == .error }
                .map { $0.offset }
                .prefix(3)

            criticalIndices.forEach { index in
                enrichedLogs[index].pinned = true
            }

            return enrichedLogs
        }

        let baseDate = Date()
        return [
            Log(
                level: .error,
                description: "Failed to decode response payload",
                timestamp: baseDate.addingTimeInterval(-30),
                metadata: ["endpoint": "/v1/items"],
                source: "Networking",
                pinned: true
            ),
            Log(
                level: .info,
                description: "Fetched 12 items from /v1/items",
                timestamp: baseDate.addingTimeInterval(-45),
                metadata: ["status": "200", "duration": "120ms"],
                source: "Networking"
            ),
            Log(
                level: .debug,
                description: "Refreshing cached configuration",
                timestamp: baseDate.addingTimeInterval(-60),
                metadata: ["feature": "RemoteConfig"],
                source: "KeepPreview"
            )
        ]
    }
}
