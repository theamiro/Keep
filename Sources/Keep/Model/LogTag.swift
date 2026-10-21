import Foundation

/// Groups log entries under a title. The first matching rule wins; entries that match nothing are "Unknown".
public struct KeepTagRule: Sendable {
    public let title: String
    let matcher: @Sendable (_ message: String, _ metadataKeys: Set<String>) -> Bool

    public init(title: String, matches: @escaping @Sendable (_ message: String, _ metadataKeys: Set<String>) -> Bool) {
        self.title = title
        matcher = matches
    }

    /// HTTP for curl-style messages and anything carrying `url` / `http.*` metadata; Memory for deinit/dealloc messages.
    public static let defaults: [KeepTagRule] = [
        KeepTagRule(title: "HTTP") { message, keys in
            message.hasPrefix("curl ") || keys.contains("url") || keys.contains { $0.hasPrefix("http.") }
        },
        KeepTagRule(title: "Memory") { message, _ in
            let words = Set(message.lowercased().split { !$0.isLetter }.map(String.init))
            return !words.isDisjoint(with: ["deinit", "dealloc", "deallocated"])
        }
    ]

    static func title(for message: String, metadataKeys: Set<String>, rules: [KeepTagRule]) -> String {
        rules.first { $0.matcher(message, metadataKeys) }?.title ?? "Unknown"
    }
}
