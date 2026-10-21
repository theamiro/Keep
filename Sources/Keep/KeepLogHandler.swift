import Foundation
import Logging

/// swift-log backend that forwards each message to the shared `KeepCore`.
/// Metadata is converted on the calling thread; redaction and storage happen on Keep's queue.
struct KeepLogHandler: LogHandler {
    var metadata = Logger.Metadata()
    var logLevel: Logger.Level
    var metadataProvider: Logger.MetadataProvider?

    private let label: String
    private let core: KeepCore

    init(label: String, core: KeepCore) {
        self.label = label
        self.core = core
        logLevel = core.configuration.minimumLevel
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicitMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level >= logLevel else { return }
        var merged = metadataProvider?.get() ?? [:]
        merged.merge(metadata) { _, new in new }
        if let explicitMetadata {
            merged.merge(explicitMetadata) { _, new in new }
        }
        core.capture(
            level: level,
            label: label,
            message: message.description,
            metadata: merged.mapValues(JSONValue.init),
            source: source,
            file: file,
            function: function,
            line: line
        )
    }
}
