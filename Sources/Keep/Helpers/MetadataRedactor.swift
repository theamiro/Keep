//
//  MetadataRedactor.swift
//  Keep
//
//  Created by Codex on 29/09/2025.
//

import Logging

/// Sanitizes metadata values by redacting sensitive keys and patterns when enabled.
///
/// The built-in sensitive-key set and regex patterns can be extended at configuration
/// time by supplying additional values through ``KeepConfiguration``.
struct MetadataRedactor {
    private let isEnabled: Bool
    private let sensitiveKeys: Set<String>
    private let sensitiveKeyFragments: [String]
    private let redactionPatterns: [String]

    init(
        isEnabled: Bool,
        additionalSensitiveKeys: Set<String> = [],
        additionalSensitiveKeyFragments: [String] = [],
        additionalRedactionPatterns: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.sensitiveKeys = Self.defaultSensitiveKeys.union(
            additionalSensitiveKeys.map { $0.lowercased() }
        )
        self.sensitiveKeyFragments = Self.defaultSensitiveKeyFragments + additionalSensitiveKeyFragments.map { $0.lowercased() }
        self.redactionPatterns = Self.defaultRedactionPatterns + additionalRedactionPatterns
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
            if sensitiveKeys.contains(loweredKey) ||
                sensitiveKeyFragments.contains(where: { loweredKey.contains($0) }) {
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
        for pattern in redactionPatterns where string.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return .string("[REDACTED]")
        }
        return .string(string)
    }

    private static let defaultSensitiveKeys: Set<String> = [
        "token", "authorization", "apikey", "api_key", "bearer",
        "password", "pass", "secret", "key", "credential", "accesskey", "privatekey",
        "ssn", "socialsecurity", "creditcard", "cardnumber", "iban", "accountnumber",
        "email", "phone", "address"
    ]

    private static let defaultRedactionPatterns: [String] = [
        #"\b\d{3}-\d{2}-\d{4}\b"#,
        #"\b\d{16}\b"#,
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        #"Bearer\s+[A-Za-z0-9\-_]+"#
    ]

    private static let defaultSensitiveKeyFragments: [String] = [
        "token", "secret", "password", "passphrase", "credential", "auth"
    ]
}
