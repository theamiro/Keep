// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Logging

#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

@MainActor
public final class Keep {
    public static private(set) var shared: Keep!

    #if canImport(UIKit)
    private let viewModel: FileLogViewModel

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
    public static func logViewController() -> FileLogViewController {
        guard let shared else {
            fatalError("Keep not correctly configured. Call `Keep.configure()` first.")
        }
        return shared.viewController
    }
    #endif
}

public final class KeepLogHandler: LogHandler, @unchecked Sendable {
    public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set(newValue) { metadata[metadataKey] = newValue }
    }

    private var logSource: LoggingSource

    public var metadata = Logging.Logger.Metadata()
    public var logLevel: Logging.Logger.Level

    private let configuration: KeepConfiguration

    public init(configuration: KeepConfiguration) {
        self.configuration = configuration
        self.logLevel = configuration.logLevel
        switch configuration.logHandler {
        case .fileSystem(let fileName):
            logSource = FileLoggingSource(fileName: fileName)
        case .inMemoryCache:
            logSource = CacheLoggingSource()
        }
    }

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
        let log = Log(
            id: UUID().uuidString,
            level: level,
            description: message.description,
            timestamp: Date(),
            metadata: combinedMetadata.isEmpty ? nil : combinedMetadata,
            source: source,
            file: file,
            function: function,
            line: line
        )
        logSource.store(log)
    }
}

public enum LoggingHandler {
    case fileSystem(_ fileName: String)
    case inMemoryCache
}

public struct KeepConfiguration {
    public let logHandler: LoggingHandler
    public let logLevel: Logging.Logger.Level

    public init(logHandler: LoggingHandler, logLevel: Logger.Level = .trace) {
        self.logHandler = logHandler
        self.logLevel = logLevel
    }
}

protocol LoggingSource {
    func store(_ log: Log)
    func flush(completion: () -> Void)
    func fetch() -> [Log]
}

class CacheLoggingSource: LoggingSource {
    var cache = Cache<String, Log>()
    func store(_ log: Log) {
        cache.insert(log, forKey: log.id)
        print("Stored in Cache Log \(log.id)")
    }

    func flush(completion: () -> Void) {
        cache.removeAll()
    }

    func fetch() -> [Log] {
        return cache.allValues()
    }
}

class FileLoggingSource: LoggingSource {
    var fileName: String
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
        var logs: [Log] = []

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                logs = try JSONDecoder().decode([Log].self, from: data)
            } catch {
                print("Failed to read or decode logs: \(error)")
            }
        }
        logs.append(log)
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL, options: [.atomicWrite])
            print("Log appended to file. \(fileURL.absoluteString)")
        } catch {
            print("Failed to write updated log file: \(error)")
        }
    }

    func flush(completion: () -> Void) {
        guard !isRunningInPreview else {
            completion()
            return
        }
        do {
            try Data().write(to: fileURL, options: .atomic)
            completion()
            print("Logs cleared successfully.")
        } catch {
            print("Failed to clear logs: \(error)")
        }
    }

    func fetch() -> [Log] {
        if isRunningInPreview {
            guard let bundledURL = bundledLogResourceURL() else {
                return []
            }
            do {
                let fileData = try Data(contentsOf: bundledURL)
                return try JSONDecoder().decode([Log].self, from: fileData).sorted(by: {
                    $0.timestamp > $1.timestamp
                })
            } catch {
                print(error)
                return []
            }
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let fileData = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Log].self, from: fileData).sorted(by: {
                $0.timestamp > $1.timestamp
            })
        } catch {
            print(error)
            return []
        }
    }

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func bundledLogResourceURL() -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension

#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: FileLoggingSource.self)
#endif

        if fileExtension.isEmpty {
            return bundle.url(forResource: name, withExtension: nil)
        }

        return bundle.url(forResource: name, withExtension: fileExtension)
    }
}

#if canImport(UIKit)
class LogMetadataCollectionCell: UICollectionViewCell {
    private var hostController: UIHostingController<LogMetadataView>?

    func configure(with metadata: Logger.Metadata?, parent: UIViewController) {
        guard let metadata else {
            hostController?.removeFromParent()
            hostController?.view.removeFromSuperview()
            hostController = nil
            return
        }
        let metadataCell = LogMetadataView(metadata: metadata)
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
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])

            hostController = controller
        }
    }
}
class LogHeaderCollectionCell: UICollectionViewCell {
    private var hostController: UIHostingController<LogLogHeaderView>?

    func configure(with log: Log, parent: UIViewController) {
        let headerCell = LogLogHeaderView(log: log)
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
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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
                controller.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            hostController = controller
        }
    }
}
#endif
