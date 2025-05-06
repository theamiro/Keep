//
//  Log.swift
//  Keep
//
//  Created by Michael Amiro on 22/04/2025.
//

import Foundation
import Logging

struct Log: Codable {
    public let id: String
    public let level: Logging.Logger.Level
    public let description: String
    public let timestamp: Date
    public let metadata: Logging.Logger.Metadata?
    public let source: String?
    public let file: String
    public let function: String
    public let line: UInt

    init(
        id: String = UUID().uuidString,
        level: Logging.Logger.Level,
        description: String,
        timestamp: Date,
        metadata: Logging.Logger.Metadata? = nil,
        source: String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.id = id
        self.level = level
        self.description = description
        self.timestamp = timestamp
        self.metadata = metadata
        self.source = source
        self.file = file
        self.function = function
        self.line = line
    }

    enum CodingKeys: String, CodingKey {
        case id
        case level
        case description
        case timestamp
        case metadata
        case source
        case file
        case function
        case line
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.level = try container.decode(Logging.Logger.Level.self, forKey: .level)
        self.description = try container.decode(String.self, forKey: .description)

        let timestamp = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.date(from: timestamp) ?? Date()

        self.metadata = try container.decodeIfPresent(Logging.Logger.Metadata.self, forKey: .metadata)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.file = try container.decode(String.self, forKey: .file)
        self.function = try container.decode(String.self, forKey: .function)
        self.line = try container.decode(UInt.self, forKey: .line)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.level, forKey: .level)
        try container.encode(self.description, forKey: .description)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: self.timestamp), forKey: .timestamp)
        try container.encodeIfPresent(self.sanitized(self.metadata), forKey: .metadata)
        try container.encodeIfPresent(self.source, forKey: .source)
        try container.encode(self.file, forKey: .file)
        try container.encode(self.function, forKey: .function)
        try container.encode(self.line, forKey: .line)
    }

    private func sanitized(_ metadata: Logger.Metadata? = nil) -> Logger.Metadata? {
        guard let metadata else { return nil }
        var copy = metadata

        if let headersValue = metadata["headers"] {
            switch headersValue {
            case .dictionary(let headersDict):
                var sanitizedDict = headersDict
                for key in sanitizedDict.keys {
                    if key.lowercased().contains("token") || key.lowercased() == "authorization" {
                        sanitizedDict[key] = .string("[REDACTED]")
                    }
                }
                copy["headers"] = .dictionary(sanitizedDict)

            default:
                break // headers exists but isn't a dictionary — nothing to sanitize
            }
        }

        return copy
    }
}

extension Log {
    func matches(_ searchTerm: String) -> Bool {
        let term = searchTerm.lowercased()

        return id.lowercased().contains(term)
            || level.rawValue.lowercased().contains(term)
            || description.lowercased().contains(term)
            || source?.lowercased().contains(term) ?? false
            || file.lowercased().contains(term)
            || function.lowercased().contains(term)
            || "\(line)".contains(term)
            || timestamp.description.lowercased().contains(term)
            || metadata?.matches(term) ?? false
    }
}
