//
//  MetadataRedactor.swift
//  Keep
//
//  Created by Codex on 29/09/2025.
//

import Logging

/// Sanitizes metadata values by redacting sensitive keys and patterns when enabled.
struct MetadataRedactor {
    private let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func sanitize(_ metadata: Logger.Metadata?) -> Logger.Metadata? {
        guard let metadata else { return nil }
        guard isEnabled else { return metadata }
        return sanitizeDictionary(metadata)
    }

    private func sanitizeDictionary(_ dict: Logger.Metadata) -> Logger.Metadata {
        var sanitized = dict
        for (key, value) in dict {
            let loweredKey = key.lowercased()
            if Self.sensitiveKeys.contains(loweredKey) {
                sanitized[key] = .string("[REDACTED]")
            } else {
                sanitized[key] = sanitizeValue(value)
            }
        }
        return sanitized
    }

    private func sanitizeValue(_ value: Logger.MetadataValue) -> Logger.MetadataValue {
        switch value {
        case .string(let string):
            return sanitizeString(string)
        case .stringConvertible(let convertible):
            return sanitizeString(String(describing: convertible))
        case .array(let array):
            return .array(array.map { sanitizeValue($0) })
        case .dictionary(let dictionary):
            return .dictionary(sanitizeDictionary(dictionary))
        @unknown default:
            return value
        }
    }

    private func sanitizeString(_ string: String) -> Logger.MetadataValue {
        for pattern in Self.redactionPatterns {
            if string.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .string("[REDACTED]")
            }
        }
        return .string(string)
    }

    private static let sensitiveKeys: Set<String> = [
        "token", "authorization", "apikey", "api_key", "bearer",
        "password", "pass", "secret", "key", "credential", "accesskey", "privatekey",
        "ssn", "socialsecurity", "creditcard", "cardnumber", "iban", "accountnumber",
        "email", "phone", "address"
    ]

    private static let redactionPatterns: [String] = [
        #"\b\d{3}-\d{2}-\d{4}\b"#,
        #"\b\d{16}\b"#,
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        #"Bearer\s+[A-Za-z0-9\-_]+"#
    ]
}
