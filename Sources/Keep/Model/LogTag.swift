//
//  LogTag.swift
//  Keep
//
//  Created by Michael Amiro on 29/09/2025.
//

import Logging

protocol LogTag {
    var title: String { get }
    func matches(metadata: Logger.Metadata?, description: String) -> Bool
}

struct NetworkTag: LogTag {
    var title: String { "HTTP" }
    func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        (metadata?.matches("http") != nil || metadata?.matches("url") != nil)
    }
}

struct MemoryTag: LogTag {
    var title: String { "Memory" }
    func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        description.contains("deinit") || description.contains("deallocate") || description.contains("init")
    }
}

struct UnknownTag: LogTag {
    var title: String { "Unknown" }
    func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        true
    }
}
