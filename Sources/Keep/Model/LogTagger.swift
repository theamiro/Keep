//
//  LogTagger.swift
//  Keep
//
//  Created by Michael Amiro on 29/09/2025.
//

import Logging

@MainActor
struct LogTagger {
    private static var registeredTags: [LogTag] = [
        NetworkTag(),
        MemoryTag(),
        UnknownTag()
    ]

    static func register(_ tag: LogTag) {
        registeredTags.insert(tag, at: registeredTags.count - 1)
    }

    static func tag(for metadata: Logger.Metadata?, description: String) -> LogTag {
        for tag in registeredTags where tag.matches(metadata: metadata, description: description) {
            return tag
        }
        return UnknownTag()
    }
}
