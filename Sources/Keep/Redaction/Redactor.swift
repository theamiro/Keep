import Foundation

/// Extra redaction rules. Redaction is always on; these only widen or narrow it.
public struct KeepRedactionPolicy: Sendable {
    /// Keys (case-insensitive) whose values are left untouched even if they look sensitive.
    public var allowedKeys: Set<String> = []
    /// Extra keys (case-insensitive) whose values are always redacted.
    public var extraKeys: Set<String> = []
    /// Extra regular expressions. Each match is replaced with `[REDACTED]`. A pattern that does not compile is not
    /// applied. Keep records it as a critical entry when it starts, and asserts in debug builds.
    public var extraPatterns: [String] = []

    public init() {}
}

/// Removes sensitive values from messages, metadata, headers, URLs and bodies before they are stored.
struct Redactor: Sendable {
    static let placeholder = "[REDACTED]"

    private static let sensitiveTokens: Set<String> = [
        "token", "auth", "authorization", "bearer", "password", "passcode", "pass", "pin", "secret",
        "credential", "credentials", "cookie", "otp", "cvv", "ssn", "iban", "email", "phone", "msisdn",
        "address", "key", "signature", "session", "sid"
    ]
    private static let sensitivePhrases: [[String]] = [
        ["api", "key"], ["access", "key"], ["private", "key"], ["card", "number"],
        ["account", "number"], ["social", "security"], ["set", "cookie"]
    ]

    private let allowedKeys: Set<String>
    private let extraKeys: Set<String>
    private let patterns: [CompiledPattern]
    /// Patterns that did not compile, built-in or custom. They are not applied.
    let rejectedPatterns: [String]

    private struct CompiledPattern: @unchecked Sendable {
        let regex: NSRegularExpression
    }

    init(policy: KeepRedactionPolicy) {
        allowedKeys = Set(policy.allowedKeys.map { $0.lowercased() })
        extraKeys = Set(policy.extraKeys.map { $0.lowercased() })
        var compiled: [CompiledPattern] = []
        var rejected: [String] = []
        for pattern in Self.builtInPatterns + policy.extraPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                compiled.append(CompiledPattern(regex: regex))
            } else {
                rejected.append(pattern)
            }
        }
        patterns = compiled
        rejectedPatterns = rejected
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

    /// Redacts sensitive query values, sensitive values in a fragment such as `#access_token=…`, and any credentials
    /// in the URL's user info.
    func redact(url: String) -> String {
        let withoutFragmentSecrets = redactFragment(in: url)
        guard var components = URLComponents(string: withoutFragmentSecrets) else {
            return replacePatterns(in: withoutFragmentSecrets)
        }
        components.user = components.user == nil ? nil : Self.placeholder
        components.password = components.password == nil ? nil : Self.placeholder
        if let items = components.queryItems {
            components.queryItems = items.map { item in
                isSensitive(key: item.name) ? URLQueryItem(name: item.name, value: Self.placeholder) : item
            }
        }
        return replacePatterns(in: components.string ?? withoutFragmentSecrets)
    }

    /// JSON bodies get key-based redaction, then every body gets the pattern pass. Form bodies (`a=b&c=d`) get
    /// key-based redaction of each pair first. Other bodies get only the pattern pass.
    func redact(body: String) -> String {
        guard let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
            let redacted = try? JSONSerialization.data(
                withJSONObject: redact(jsonObject: object),
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
        else {
            return replacePatterns(in: redactFormPairs(in: body))
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

    /// Form bodies and URL fragments: redacts the value of each `key=value` pair whose key is sensitive. Pairs without
    /// `=`, and keys with spaces, are left to the pattern pass, so ordinary sentences are not reshaped.
    private func redactFormPairs(in text: String) -> String {
        guard text.contains("=") else { return text }
        return text.components(separatedBy: "&").map { pair -> String in
            guard let equals = pair.firstIndex(of: "=") else { return pair }
            let rawKey = pair[..<equals]
            guard !rawKey.isEmpty, !rawKey.contains(where: \.isWhitespace) else { return pair }
            let key = String(rawKey).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(rawKey)
            return isSensitive(key: key) ? "\(rawKey)=\(Self.placeholder)" : pair
        }.joined(separator: "&")
    }

    /// An OAuth implicit-flow token arrives in the fragment, as in `#access_token=…&expires_in=3600`.
    private func redactFragment(in url: String) -> String {
        guard let hash = url.firstIndex(of: "#") else { return url }
        let fragment = String(url[url.index(after: hash)...])
        return String(url[...hash]) + redactFormPairs(in: fragment)
    }

    private func replacePatterns(in text: String) -> String {
        var result = text
        for pattern in patterns {
            result = Self.replace(pattern.regex, in: result)
        }
        return Self.replaceCardNumbers(in: redactKeyValuePairs(in: result))
    }

    /// Free text such as log messages, error text and header values. Redacts the value of every `key: value` or
    /// `key=value` pair whose key is sensitive, including JSON pairs such as `"token":"x"` and escaped ones.
    private func redactKeyValuePairs(in text: String) -> String {
        guard let regex = Self.keyValueRegex else { return text }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard isSensitive(key: nsText.substring(with: match.range(at: 2))) else { continue }
            let valueRange = match.range(at: 3)
            result += nsText.substring(with: NSRange(location: cursor, length: valueRange.location - cursor))
            result += Self.placeholder
            cursor = valueRange.location + valueRange.length
        }
        result += nsText.substring(from: cursor)
        return result
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

    /// A key of letters, digits, `_`, `.` or `-`, optionally quoted (escaped quotes too), then `:` or `=`, then a
    /// value. The value is a quoted string, or a run up to whitespace, `,`, `;`, `&` or a quote. The key is checked
    /// by `isSensitive(key:)`, so the list of key words lives in one place.
    private static let keyValueRegex = try? NSRegularExpression(
        pattern: #"(\\?["']?)\b([A-Za-z][\w.-]{0,63})\\?\1\s*[:=]\s*(\\?"[^"\r\n]*"?|\\?'[^'\r\n]*'?|[^\s,;&'"]+)"#
    )

    /// Each pattern keeps any leading group it captures (e.g. the "Bearer " scheme word) and replaces the rest.
    /// Runs are bounded, and the bounded runs are possessive where the next character is not in the run's class, so
    /// the engine never backtracks through a long run. The JWT starts only where a run of its characters begins, so
    /// a long run of `eyJ-` is scanned once, not once per `eyJ`. Without these limits a 100k-character run stalled
    /// capture.
    private static let builtInPatterns: [String] = [
        #"(\b(?:bearer|basic)\s+)[A-Za-z0-9._~+/=\-]+"#,
        #"()(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{1,4096}+\.[A-Za-z0-9_-]{1,4096}+\.[A-Za-z0-9_-]{1,4096}"#,
        #"()[A-Z0-9._%+-]{1,64}+@[A-Z0-9.-]{1,253}\.[A-Z]{2,}"#,
        #"()\+\d{8,15}\b"#,
        #"()\b\d{3}-\d{2}-\d{4}\b"#
    ]
}
