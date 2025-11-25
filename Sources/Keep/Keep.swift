// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Logging

#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// Primary entry point for configuring Keep and presenting the bundled log viewer.
@MainActor
public final class Keep {
    public static private(set) var shared: Keep!

    #if canImport(UIKit)
    private let viewModel: FileLogViewModel

    /// Shared instance of the UIKit log viewer backed by the configured `FileLogViewModel`.
    public lazy var viewController: FileLogViewController = {
        FileLogViewController(viewModel: self.viewModel)
    }()
    #endif

    private init(configuration: KeepConfiguration) {
        #if canImport(UIKit)
        self.viewModel = FileLogViewModel(configuration: configuration)
        #else
        _ = configuration
        #endif
    }

    /// Configures Keep once during application launch.
    ///
    /// Call this method before logging any messages or requesting the bundled log viewer.
    /// Subsequent calls are ignored so it is safe to guard repeated invocations.
    /// - Parameter configuration: Logging behaviour, including destination and minimum level.
    public static func configure(
        with configuration: KeepConfiguration = KeepConfiguration(
            logHandler: .fileSystem("log.json"), logLevel: .trace)
    ) {
        guard shared == nil else {
            return
        }
        shared = Keep(configuration: configuration)
    }

    #if canImport(UIKit)
    /// Returns the shared log viewer configured through `Keep.configure`.
    ///
    /// - Returns: A `FileLogViewController` bound to the shared `FileLogViewModel`.
    /// - Precondition: `Keep.configure` must be called before requesting the view controller.
    public static func logViewController() -> FileLogViewController {
        guard let shared else {
            fatalError("Keep not correctly configured. Call `Keep.configure()` first.")
        }
        return shared.viewController
    }
    #endif
}

/// `LogHandler` implementation that forwards messages to the configured `LoggingSource`.
public final class KeepLogHandler: LogHandler, @unchecked Sendable {
    /// Access and mutate metadata that should be applied to each log entry.
    public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { stateQueue.sync { _metadata[metadataKey] } }
        set(newValue) {
            stateQueue.sync {
                _metadata[metadataKey] = newValue
            }
        }
    }

    private var logSource: LoggingSource
    private let stateQueue = DispatchQueue(label: "com.keep.logging.handler.state")

    /// Default metadata merged into every logged entry unless overridden at call time.
    public var metadata: Logging.Logger.Metadata {
        get { stateQueue.sync { _metadata } }
        set { stateQueue.sync { _metadata = newValue } }
    }
    /// Minimum severity that will be recorded by this handler.
    public var logLevel: Logging.Logger.Level {
        get { stateQueue.sync { _logLevel } }
        set { stateQueue.sync { _logLevel = newValue } }
    }

    private var _metadata = Logging.Logger.Metadata()
    private var _logLevel: Logging.Logger.Level

    private let configuration: KeepConfiguration
    private let metadataRedactor: MetadataRedactor

    /// Creates a log handler instance that writes to the destination described by the configuration.
    ///
    /// - Parameter configuration: Global logging configuration shared with `Keep`.
    public init(configuration: KeepConfiguration) {
        self.configuration = configuration
        self.metadataRedactor = MetadataRedactor(isEnabled: configuration.redactsSensitiveInformation)
        self._logLevel = configuration.logLevel
        switch configuration.logHandler {
        case .fileSystem(let fileName):
            logSource = FileLoggingSource(fileName: fileName)
        case .inMemoryCache:
            logSource = InMemoryLoggingSource.shared
        }
    }

    /// Records the supplied message in the active logging destination.
    ///
    /// The handler merges metadata supplied through the `LogHandler` protocol with the
    /// per-call metadata argument, redacting sensitive keys before persisting the entry when configured to do so.
    /// - Parameters:
    ///   - level: Severity of the log message.
    ///   - message: Human readable payload emitted by the caller.
    ///   - metadata: Optional metadata that should override the handler default values.
    ///   - source: The subsystem generating the log message.
    ///   - file: The originating file identifier.
    ///   - function: The function that produced the log entry.
    ///   - line: Line number in the originating file.
    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        var combinedMetadata = self.metadata
        if let metadata {
            combinedMetadata.merge(metadata, uniquingKeysWith: { _, new in new })
        }
        let sanitizedMetadata = metadataRedactor.sanitize(combinedMetadata.isEmpty ? nil : combinedMetadata)
        let log = Log(
            id: UUID().uuidString,
            level: level,
            description: message.description,
            timestamp: Date(),
            metadata: sanitizedMetadata,
            source: source,
            file: file,
            function: function,
            line: line
        )
        logSource.store(log)
    }
}

/// Supported backing stores for log persistence.
public enum LoggingHandler {
    /// Persists logs to a JSON file inside the application's documents directory.
    case fileSystem(_ fileName: String)
    /// Keeps logs exclusively in memory for the duration of the process.
    case inMemoryCache
}

/// Configuration object describing how Keep should capture and present logs.
public struct KeepConfiguration {
    public let logHandler: LoggingHandler
    public let logLevel: Logging.Logger.Level
    public let redactsSensitiveInformation: Bool

    /// Creates a new configuration value.
    ///
    /// - Parameters:
    ///   - logHandler: Destination for captured log entries.
    ///   - logLevel: Minimum level that should be recorded by `KeepLogHandler`.
    ///   - redactsSensitiveInformation: When `true`, metadata is sanitized before persistence.
    public init(
        logHandler: LoggingHandler,
        logLevel: Logger.Level = .trace,
        redactsSensitiveInformation: Bool = true
    ) {
        self.logHandler = logHandler
        self.logLevel = logLevel
        self.redactsSensitiveInformation = redactsSensitiveInformation
    }
}

protocol LoggingSource {
    func store(_ log: Log)
    func update(log: Log)
    func deleteLog(withID id: String)
    func flush(completion: () -> Void)
    func fetch() -> [Log]
}

final class CacheLoggingSource: LoggingSource {
    private let cache = Cache<String, Log>()
    func store(_ log: Log) {
        cache.insert(log, forKey: log.id)
    }

    func update(log: Log) {
        cache.insert(log, forKey: log.id)
    }

    func deleteLog(withID id: String) {
        cache.removeValue(forKey: id)
    }

    func flush(completion: () -> Void) {
        cache.removeAll()
        completion()
    }

    func fetch() -> [Log] {
        return sortLogs(cache.allValues())
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

final class FileLoggingSource: LoggingSource {
    private let fileName: String
    private var fileURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(fileName)
    }

    init(fileName: String) {
        self.fileName = fileName
    }

    func store(_ log: Log) {
        guard !isRunningInPreview else {
            return
        }
        var logs = loadLogs()
        logs.append(log)
        persist(logs)
    }

    func update(log: Log) {
        guard !isRunningInPreview else {
            return
        }
        var logs = loadLogs()
        guard let index = logs.firstIndex(where: { $0.id == log.id }) else {
            return
        }
        logs[index] = log
        persist(logs)
    }

    func deleteLog(withID id: String) {
        guard !isRunningInPreview else {
            return
        }
        let logs = loadLogs()
        let newLogs = logs.filter { $0.id != id }
        guard newLogs.count != logs.count else {
            return
        }
        persist(newLogs)
    }

    func flush(completion: () -> Void) {
        guard !isRunningInPreview else {
            completion()
            return
        }
        do {
            try Data().write(to: fileURL, options: .atomic)
            completion()
        } catch {
            completion()
            assertionFailure("Failed to clear logs: \(error)")
        }
    }

    func fetch() -> [Log] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let fileData = try Data(contentsOf: fileURL)
            guard !fileData.isEmpty else { return [] }
            return sortLogs(try JSONDecoder().decode([Log].self, from: fileData))
        } catch {
            assertionFailure("Failed to load logs from disk: \(error)")
            return []
        }
    }

    private func loadLogs() -> [Log] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [] }
            return try JSONDecoder().decode([Log].self, from: data)
        } catch {
            assertionFailure("Failed to decode existing logs: \(error)")
            return []
        }
    }

    private func persist(_ logs: [Log]) {
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL, options: [.atomicWrite])
        } catch {
            assertionFailure("Failed to persist logs: \(error)")
        }
    }

    private func sortLogs(_ logs: [Log]) -> [Log] {
        logs.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

#if canImport(UIKit)
class LogMetadataCollectionCell: UICollectionViewCell {
    private var hostController: UIHostingController<LogMetadataView>?

    func configure(with metadata: Logger.Metadata?, parent: ToastPresentable) {
        guard let metadata else {
            hostController?.removeFromParent()
            hostController?.view.removeFromSuperview()
            hostController = nil
            return
        }
        var metadataCell = LogMetadataView(metadata: metadata)
        metadataCell.pasteCompletion = { [weak parent] in
            parent?.showPopup(message: "Copied to clipboard")
        }
        if let hostController = hostController {
            hostController.rootView = metadataCell
            hostController.view.invalidateIntrinsicContentSize()
        } else {
            let controller = UIHostingController(rootView: metadataCell)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.backgroundColor = .clear

            parent.addChild(controller)
            contentView.addSubview(controller.view)
            controller.didMove(toParent: parent)

            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            hostController = controller
        }
    }
}

class LogHeaderCollectionCell: UICollectionViewCell {
    private var hostController: UIHostingController<LogLogHeaderView>?

    func configure(with log: Log, parent: (UIViewController & ToastPresentable)) {
        var headerCell = LogLogHeaderView(log: log)
        headerCell.pasteCompletion = { [weak parent] in
            parent?.showPopup(message: "Copied to clipboard")
        }
        if let hostController = hostController {
            hostController.rootView = headerCell
            hostController.view.invalidateIntrinsicContentSize()
        } else {
            let controller = UIHostingController(rootView: headerCell)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.backgroundColor = .clear

            parent.addChild(controller)
            contentView.addSubview(controller.view)
            controller.didMove(toParent: parent)

            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            hostController = controller
        }
    }
}

class LogCell: UITableViewCell {
    private var hostController: UIHostingController<LogViewCell>?

    func configure(with log: Log, parent: UIViewController) {
        let logViewCell = LogViewCell(log: log)
        if let hostController = hostController {
            hostController.rootView = logViewCell
            hostController.view.invalidateIntrinsicContentSize()
        } else {
            let controller = UIHostingController(rootView: logViewCell)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.backgroundColor = .clear

            parent.addChild(controller)
            contentView.addSubview(controller.view)
            controller.didMove(toParent: parent)

            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            hostController = controller
        }
    }
}

class TitleHeaderReusableViewCell: UICollectionReusableView {
    private var hostController: UIHostingController<TitleHeaderView>?

    func configure(title: String, parent: UIViewController) {
        let headerCell = TitleHeaderView(title: title)
        if let hostController = hostController {
            hostController.rootView = headerCell
            hostController.view.invalidateIntrinsicContentSize()
        } else {
            let controller = UIHostingController(rootView: headerCell)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.backgroundColor = .clear

            parent.addChild(controller)
            addSubview(controller.view)
            controller.didMove(toParent: parent)

            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            hostController = controller
        }
    }
}
#endif
