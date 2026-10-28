import Foundation

/// Extra redaction rules. Redaction is always on; these only widen or narrow it.
public struct KeepRedactionPolicy: Sendable {
    /// Keys (case-insensitive) whose values are left untouched even if they look sensitive.
    public var allowedKeys: Set<String> = []
    /// Extra keys (case-insensitive) whose values are always redacted.
    public var extraKeys: Set<String> = []
    /// Extra regular expressions. Each match is replaced with `[REDACTED]`. Invalid patterns are ignored.
    public var extraPatterns: [String] = []

    public init() {}
}

/// Removes sensitive values from messages, metadata, headers, URLs and bodies before they are stored.
struct Redactor: Sendable {
    static let placeholder = "[REDACTED]"

    private static let sensitiveTokens: Set<String> = [
        "token", "auth", "authorization", "bearer", "password", "passcode", "pass", "pin", "secret",
        "credential", "credentials", "cookie", "otp", "cvv", "ssn", "iban", "email", "phone", "msisdn",
        "address", "key"
    ]
    private static let sensitivePhrases: [[String]] = [
        ["api", "key"], ["access", "key"], ["private", "key"], ["card", "number"],
        ["account", "number"], ["social", "security"], ["set", "cookie"]
    ]

    private let allowedKeys: Set<String>
    private let extraKeys: Set<String>
    private let patterns: [CompiledPattern]

    private struct CompiledPattern: @unchecked Sendable {
        let regex: NSRegularExpression
    }

    init(policy: KeepRedactionPolicy) {
        allowedKeys = Set(policy.allowedKeys.map { $0.lowercased() })
        extraKeys = Set(policy.extraKeys.map { $0.lowercased() })
        patterns = (Self.builtInPatterns + policy.extraPatterns).compactMap { pattern in
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map(CompiledPattern.init)
        }
    }

    // MARK: Public entry points

    func redact(message: String) -> String {
        replacePatterns(in: message)
    }

    func redact(metadata: [String: JSONValue]) -> [String: JSONValue] {
        metadata.reduce(into: [:]) { result, pair in
            result[pair.key] = isSensitive(key: pair.key) ? .string(Self.placeholder) : redact(value: pair.value)
        }
    }

    func redact(headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { result, pair in
            result[pair.key] = isSensitive(key: pair.key) ? Self.placeholder : replacePatterns(in: pair.value)
        }
    }

    /// Redacts sensitive query values and any credentials in the URL's user info.
    func redact(url: String) -> String {
        guard var components = URLComponents(string: url) else {
            return replacePatterns(in: url)
        }
        components.user = components.user == nil ? nil : Self.placeholder
        components.password = components.password == nil ? nil : Self.placeholder
        if let items = components.queryItems {
            components.queryItems = items.map { item in
                isSensitive(key: item.name) ? URLQueryItem(name: item.name, value: Self.placeholder) : item
            }
        }
        return replacePatterns(in: components.string ?? url)
    }

    /// JSON bodies get key-based redaction, then every body gets the pattern pass. Non-JSON bodies get only the pattern pass.
    func redact(body: String) -> String {
        guard let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
            let redacted = try? JSONSerialization.data(
                withJSONObject: redact(jsonObject: object),
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
        else {
            return replacePatterns(in: body)
        }
        return replacePatterns(in: String(decoding: redacted, as: UTF8.self))
    }

    // MARK: Keys

    func isSensitive(key: String) -> Bool {
        let lowered = key.lowercased()
        if allowedKeys.contains(lowered) {
            return false
        }
        if extraKeys.contains(lowered) {
            return true
        }
        let tokens = Self.tokens(of: key)
        if !Self.sensitiveTokens.isDisjoint(with: tokens) {
            return true
        }
        return Self.sensitivePhrases.contains { phrase in
            tokens.indices.dropLast(phrase.count - 1).contains { start in
                Array(tokens[start..<start + phrase.count]) == phrase
            }
        }
    }

    /// Splits `authorization_token`, `apiKey`, `X-Api-Key` and `author` into lowercase words.
    static func tokens(of key: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var previousWasLowercase = false
        for character in key {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty {
                    tokens.append(current)
                }
                current = ""
                previousWasLowercase = false
                continue
            }
            if character.isUppercase, previousWasLowercase, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current += character.lowercased()
            previousWasLowercase = character.isLowercase
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    // MARK: Values

    private func redact(value: JSONValue) -> JSONValue {
        switch value {
        case .string(let string):
            return .string(replacePatterns(in: string))
        case .array(let array):
            return .array(array.map(redact(value:)))
        case .object(let object):
            return .object(redact(metadata: object))
        }
    }

    private func redact(jsonObject: Any) -> Any {
        if let dictionary = jsonObject as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = isSensitive(key: pair.key) ? Self.placeholder : redact(jsonObject: pair.value)
            }
        }
        if let array = jsonObject as? [Any] {
            return array.map(redact(jsonObject:))
        }
        if let string = jsonObject as? String {
            return replacePatterns(in: string)
        }
        return jsonObject
    }

    private func replacePatterns(in text: String) -> String {
        var result = text
        for pattern in patterns {
            result = Self.replace(pattern.regex, in: result)
        }
        return Self.replaceCardNumbers(in: result)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1\(placeholder)")
    }

    /// Card numbers are only redacted when they pass the Luhn check, which avoids masking order numbers and timestamps.
    private static func replaceCardNumbers(in text: String) -> String {
        guard let regex = cardRegex else { return text }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let digits = nsText.substring(with: match.range).filter(\.isNumber)
            result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += isLuhnValid(digits) ? placeholder : nsText.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }

    static func isLuhnValid(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    private static let cardRegex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]?){12,18}\d\b"#)

    /// Each pattern keeps any leading group it captures (e.g. the "Bearer " scheme word) and replaces the rest.
    private static let builtInPatterns: [String] = [
        #"(\b(?:bearer|basic)\s+)[A-Za-z0-9._~+/=\-]+"#,
        #"(\b(?:authorization|cookie|set-cookie|x-api-key|api[-_ ]?key|password|passcode|secret|token)\s*[:=]\s*)[^\s,;'"&]+"#,
        #"()\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
        #"()[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        #"()\+\d{8,15}\b"#,
        #"()\b\d{3}-\d{2}-\d{4}\b"#
    ]
}
