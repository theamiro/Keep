// The Swift Programming Language
// https://docs.swift.org/swift-book

import Logging
import SwiftUI
import UIKit

@available(iOS 13.0, *)
@MainActor
public class Keep {
  public static private(set) var shared: Keep!

  private let viewModel: FileLogViewModel

  public lazy var viewController: FileLogViewController = {
    let controller = FileLogViewController(viewModel: self.viewModel)
    return controller
  }()

  private init(configuration: KeepConfiguration) {
    self.viewModel = FileLogViewModel(configuration: configuration)
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

  public static func logViewController() -> FileLogViewController {
    guard let shared else {
      fatalError("Keep not correctly configured. Call `Keep.configure()` first.")
    }
    return shared.viewController
  }
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
    let log = Log(
      id: UUID().uuidString,
      level: level,
      description: message.description,
      timestamp: Date(),
      metadata: metadata,
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

  init(fileName: String) {
    self.fileName = fileName
  }

  func store(_ log: Log) {
    var logs: [Log] = []
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)

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
    guard
      let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      return
    }
    let fileURL = documentsURL.appendingPathComponent(fileName)
    do {
      try Data().write(to: fileURL, options: .atomic)
      completion()
      print("Logs cleared successfully.")
    } catch {
      print("Failed to clear logs: \(error)")
    }
  }

  func fetch() -> [Log] {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsURL.appendingPathComponent(fileName)
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
}

@available(iOS 13.0, *)
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

@available(iOS 13.0, *)
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

@available(iOS 13.0, *)
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

@available(iOS 13.0, *)
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
