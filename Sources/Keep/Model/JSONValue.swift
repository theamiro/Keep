import Foundation
import Logging

/// A Sendable, Codable form of swift-log metadata. Keep converts metadata to this once, on the caller's thread,
/// so redaction and storage never touch swift-log's non-Sendable values.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(_ value: Logger.MetadataValue) {
        switch value {
        case let .string(string):
            self = .string(string)
        case let .stringConvertible(convertible):
            self = .string(convertible.description)
        case let .array(array):
            self = .array(array.map(JSONValue.init))
        case let .dictionary(dictionary):
            self = .object(dictionary.mapValues(JSONValue.init))
        @unknown default:
            self = .string(String(describing: value))
        }
    }

    init(metadata: Logger.Metadata) {
        self = .object(metadata.mapValues(JSONValue.init))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(string): try container.encode(string)
        case let .array(array): try container.encode(array)
        case let .object(object): try container.encode(object)
        }
    }

    /// A plain-text rendering used for search and the text report.
    var text: String {
        switch self {
        case let .string(string): return string
        case let .array(array): return "[" + array.map(\.text).joined(separator: ", ") + "]"
        case let .object(object):
            return "{" + object.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }.joined(separator: ", ") + "}"
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Pretty-printed JSON used by the detail screens and the JSON exports.
    func prettyJSON() -> String {
        guard let data = try? KeepCodec.encoder(pretty: true).encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
