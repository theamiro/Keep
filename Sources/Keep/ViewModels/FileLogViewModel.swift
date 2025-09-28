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
        FileLogViewModel(configuration: .init(logHandler: .fileSystem("log.json"), logLevel: .trace))
    }

    public init(configuration: KeepConfiguration) {
        self.configuration = configuration
        switch configuration.logHandler {
        case .fileSystem(let fileName):
            loggingSource = FileLoggingSource(fileName: fileName)
        case .inMemoryCache:
            loggingSource = CacheLoggingSource()
        }
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
