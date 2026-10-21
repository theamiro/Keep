import Foundation
import Logging

/// One message captured from swift-log (see "Log entry" in CONTEXT.md).
public struct LogEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Monotonic per process; breaks ties between entries captured in the same timestamp.
    public let sequence: Int
    public let timestamp: Date
    public let level: Logger.Level
    public let label: String
    public let message: String
    public let metadata: [String: JSONValue]
    public let source: String
    public let file: String
    public let function: String
    public let line: UInt
    public let tag: String
    public var isPinned: Bool

    init(
        id: String = UUID().uuidString,
        sequence: Int,
        timestamp: Date,
        level: Logger.Level,
        label: String,
        message: String,
        metadata: [String: JSONValue],
        source: String,
        file: String,
        function: String,
        line: UInt,
        tag: String,
        isPinned: Bool = false
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.message = message
        self.metadata = metadata
        self.source = source
        self.file = file
        self.function = function
        self.line = line
        self.tag = tag
        self.isPinned = isPinned
    }

    /// Case-insensitive search across the fields a tester is likely to look for.
    func matches(_ term: String) -> Bool {
        let needle = term.lowercased()
        guard !needle.isEmpty else { return true }
        return message.lowercased().contains(needle)
            || label.lowercased().contains(needle)
            || tag.lowercased().contains(needle)
            || file.lowercased().contains(needle)
            || function.lowercased().contains(needle)
            || level.rawValue.lowercased().contains(needle)
            || metadata.contains { $0.key.lowercased().contains(needle) || $0.value.text.lowercased().contains(needle) }
    }
}
