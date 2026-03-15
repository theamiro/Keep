//
//  LogTagService.swift
//  Keep
//
//  Created by Michael Amiro on 15/03/2026.
//

import Logging

/// Resolves the appropriate ``LogTag`` for a given log entry.
///
/// The service evaluates tags in registration order, returning the first match.
/// ``UnknownTag`` is always the last-resort fallback.
///
/// Register custom tags before configuring Keep:
/// ```swift
/// let tagService = LogTagService()
/// tagService.register(AnalyticsTag())
/// Keep.configure(with: KeepConfiguration(logHandler: .inMemoryCache, tagService: tagService))
/// ```
public final class LogTagService {
    private var tags: [any LogTag]

    /// Creates a service pre-loaded with the built-in ``NetworkTag``, ``MemoryTag``,
    /// and ``UnknownTag`` fallback.
    public init() {
        tags = [NetworkTag(), MemoryTag(), UnknownTag()]
    }

    /// Registers a custom tag that is evaluated before the built-in ``UnknownTag`` fallback.
    ///
    /// Call this method for each custom tag before passing the service to ``KeepConfiguration``.
    /// Tags are evaluated in registration order; the first match wins.
    public func register(_ tag: any LogTag) {
        // Insert before UnknownTag so the fallback remains last.
        let insertionIndex = max(tags.count - 1, 0)
        tags.insert(tag, at: insertionIndex)
    }

    /// Returns the first tag whose ``LogTag/matches(metadata:description:)`` returns `true`.
    func tag(for metadata: Logger.Metadata?, description: String) -> any LogTag {
        tags.first { $0.matches(metadata: metadata, description: description) } ?? UnknownTag()
    }
}

extension LogTagService {
    /// Shared default service used by the ``Log/tag`` convenience accessor and the bundled views.
    ///
    /// This is automatically replaced with the service supplied in ``KeepConfiguration`` when
    /// ``Keep/configure(with:)`` is called, so custom tags registered before configuration
    /// are reflected in all views.
    static var `default` = LogTagService()
}
