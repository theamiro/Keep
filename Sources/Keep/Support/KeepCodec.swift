import Foundation

/// JSON settings shared by the on-disk snapshot, the JSON Lines export and the device/HAR output.
enum KeepCodec {
    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let formatter = ISOFormatter()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting =
            pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let formatter = ISOFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(text)")
            }
            return date
        }
        return decoder
    }

    /// Formats a date the way the viewer shows it (local time, seconds precision).
    static func displayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

/// Wraps the formatter so one instance can be used from a @Sendable coding closure. Each encoder or decoder owns its own.
private final class ISOFormatter: @unchecked Sendable {
    private let formatter: ISO8601DateFormatter

    init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    func date(from text: String) -> Date? {
        formatter.date(from: text)
    }
}

extension NSLock {
    /// Runs `body` while holding the lock.
    func locked<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
