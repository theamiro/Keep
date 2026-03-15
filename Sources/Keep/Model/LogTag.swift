//
//  LogTag.swift
//  Keep
//
//  Created by Michael Amiro on 29/09/2025.
//

import Logging

/// Describes a category that can be applied to a log entry.
///
/// Implement this protocol to create a custom tag and register it with a ``LogTagService``.
public protocol LogTag {
    /// Short human-readable label displayed in the log viewer.
    var title: String { get }
    /// Returns `true` when this tag applies to the given log entry.
    func matches(metadata: Logger.Metadata?, description: String) -> Bool
}

/// Tags logs that involve HTTP network activity.
///
/// A log is classified as HTTP when its metadata contains a key or value referencing
/// "http" or "url" (case-insensitive).
public struct NetworkTag: LogTag {
    public init() {}
    public var title: String { "HTTP" }
    public func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        metadata?.matches("http") == true || metadata?.matches("url") == true
    }
}

/// Tags logs related to object lifecycle events (init / deinit / deallocation).
///
/// Matching uses word boundaries so common words such as "initialize" or
/// "initialization" are **not** classified as memory events.
public struct MemoryTag: LogTag {
    public init() {}
    public var title: String { "Memory" }
    public func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        description.range(
            of: #"\b(init|deinit|deallocate)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

/// Fallback tag applied when no other tag matches.
public struct UnknownTag: LogTag {
    public init() {}
    public var title: String { "Unknown" }
    public func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        true
    }
}
