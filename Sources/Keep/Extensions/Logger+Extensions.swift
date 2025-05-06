//
//  Logger+Extensions.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import SwiftUI
import Logging

@available(iOS 13.0, *)
extension Logging.Logger.Level {
    public var color: Color {
        switch self {
        case .trace:
            return Color.gray
        case .debug:
            return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .info:
            return Color.green
        case .notice:
            return Color(red: 0.0, green: 0.6, blue: 0.8)
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        case .critical:
            return Color(red: 0.8, green: 0.0, blue: 0.4)
        }
    }
}

extension Logger.Metadata {
    func matches(_ term: String) -> Bool {
        for (key, value) in self {
            if key.lowercased().contains(term) || value.description.lowercased().contains(term) {
                return true
            }
        }
        return false
    }
}

extension Logger.MetadataValue: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dict):
            try container.encode(dict)
        case .stringConvertible(let convertible):
            try container.encode(convertible.description)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([Logger.MetadataValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: Logger.MetadataValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode Logger.MetadataValue"
            )
        }
    }
}
