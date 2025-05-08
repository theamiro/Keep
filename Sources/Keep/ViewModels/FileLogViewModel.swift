//
//  FileLogViewModel.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import Foundation
import Logging
import Combine

@available(iOS 13.0, *)
public final class FileLogViewModel: ObservableObject {
    private let loggingSource: LoggingSource
    private let configuration: KeepConfiguration

    @Published var searchTerm: String = ""
    @Published var selectedLevel: Logging.Logger.Level?

    @Published private(set) var logs: [Log] = []
    private var allLogs: [Log] = []

    private var cancellables = Set<AnyCancellable>()

    static var preview: FileLogViewModel {
        return FileLogViewModel(configuration: .init(logHandler: .fileSystem("preview"), logLevel: .trace))
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
        allLogs = fetchedLogs
        logs = fetchedLogs
    }

    func clearLogs(completion: @escaping () -> Void) {
        loggingSource.flush {
            completion()
        }
    }

    private func filterLogs() {
        logs = allLogs.filter { [weak self] log in
            guard let self = self else { return false }
            let matchesSearch = searchTerm.isEmpty || log.matches(searchTerm)
            let matchesLevel = selectedLevel == nil || log.level == selectedLevel
            return matchesSearch && matchesLevel
        }
    }
}
