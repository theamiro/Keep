import Foundation

/// A token category used by the JSON formatter and syntax-aware viewers.
enum JSONTokenKind: Sendable {
    case key
    case string
    case number
    case literal
    case punctuation
}

/// A string formatted for display, with token ranges measured in UTF-16 units.
struct FormattedText: Sendable {
    struct Span: Sendable {
        let kind: JSONTokenKind
        let range: NSRange
    }

    let text: String
    let spans: [Span]
}

private struct ParseResult {
    let formatted: FormattedText
    let isComplete: Bool
    let end: String.Index
}

/// Pretty-prints JSON for display without changing the captured value.
enum JSONFormatter {
    /// Formats a JSON value with two-space indentation, retaining its original key order.
    /// Incomplete input is formatted up to the first unparseable token and its remaining text is kept verbatim.
    static func format(_ text: String) -> FormattedText? {
        parse(text)?.formatted
    }

    /// Finds the first balanced object or array embedded in a string, such as a URL/status followed by JSON.
    static func splitEmbedded(_ string: String) -> (prefix: String, json: String)? {
        for index in string.indices where string[index] == "{" || string[index] == "[" {
            let suffix = String(string[index...])
            guard let parsed = parse(suffix), parsed.isComplete else { continue }
            let remainder = suffix[parsed.end...]
            guard remainder.allSatisfy(\.isWhitespace) else { continue }
            let json = String(suffix[..<parsed.end]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(string[..<index]), json)
        }
        return nil
    }

    /// Finds an embedded object candidate without validating it, for large strings that are parsed off the UI queue.
    static func embeddedCandidate(_ string: String) -> (prefix: String, json: String)? {
        guard let index = string.indices.first(where: { string[$0] == "{" || string[$0] == "[" }) else {
            return nil
        }
        return (String(string[..<index]), String(string[index...]))
    }

    private static func parse(_ text: String) -> ParseResult? {
        var lexer = Lexer(text: text)
        let tokens = lexer.tokens()
        guard !tokens.isEmpty else { return nil }

        var parser = Parser(text: text, tokens: tokens, failedAt: lexer.failedAt)
        guard parser.parseValue(depth: 0) else { return nil }
        parser.appendUnparsedTail()
        return ParseResult(
            formatted: FormattedText(text: parser.output, spans: parser.spans),
            isComplete: parser.isComplete,
            end: parser.rootEnd ?? text.endIndex
        )
    }
}

private struct Parser {
    let text: String
    let tokens: [Token]
    let failedAt: String.Index?
    private(set) var position = 0
    private(set) var output = ""
    private(set) var spans: [FormattedText.Span] = []
    private(set) var isComplete = true
    private(set) var rootEnd: String.Index?

    mutating func parseValue(depth: Int) -> Bool {
        guard let token = current else { return false }
        switch token.kind {
        case .objectStart: return parseObject(depth: depth)
        case .arrayStart: return parseArray(depth: depth)
        case .string:
            append(token.text, kind: .string)
            advance()
            return true
        case .number:
            append(token.text, kind: .number)
            advance()
            return true
        case .literal:
            append(token.text, kind: .literal)
            advance()
            return true
        default: return false
        }
    }

    mutating func appendUnparsedTail() {
        if let token = current {
            isComplete = false
            output += text[token.start...]
        } else if let failedAt, failedAt < text.endIndex {
            isComplete = false
            output += text[failedAt...]
        } else if let rootEnd {
            let trailing = text[rootEnd...]
            if !trailing.allSatisfy(\.isWhitespace) {
                isComplete = false
                output += trailing
            }
        }
    }

    private mutating func parseObject(depth: Int) -> Bool {
        guard let opening = current, opening.kind == .objectStart else { return false }
        append("{", kind: .punctuation)
        advance()
        guard let first = current else {
            isComplete = false
            return true
        }
        if first.kind == .objectEnd {
            append("}", kind: .punctuation)
            rootEnd = end(after: first)
            advance()
            return true
        }

        output += "\n"
        while true {
            guard let key = current, key.kind == .string else {
                isComplete = false
                return true
            }
            indent(depth + 1)
            append(key.text, kind: .key)
            advance()
            guard let colon = current, colon.kind == .colon else {
                isComplete = false
                return true
            }
            append(":", kind: .punctuation)
            output += " "
            advance()
            guard parseValue(depth: depth + 1) else {
                isComplete = false
                return true
            }

            guard let separator = current else {
                isComplete = false
                return true
            }
            if separator.kind == .comma {
                append(",", kind: .punctuation)
                output += "\n"
                advance()
                continue
            }
            guard separator.kind == .objectEnd else {
                isComplete = false
                return true
            }
            output += "\n"
            indent(depth)
            append("}", kind: .punctuation)
            rootEnd = end(after: separator)
            advance()
            return true
        }
    }

    private mutating func parseArray(depth: Int) -> Bool {
        guard let opening = current, opening.kind == .arrayStart else { return false }
        append("[", kind: .punctuation)
        advance()
        guard let first = current else {
            isComplete = false
            return true
        }
        if first.kind == .arrayEnd {
            append("]", kind: .punctuation)
            rootEnd = end(after: first)
            advance()
            return true
        }

        output += "\n"
        while true {
            indent(depth + 1)
            guard parseValue(depth: depth + 1) else {
                isComplete = false
                return true
            }
            guard let separator = current else {
                isComplete = false
                return true
            }
            if separator.kind == .comma {
                append(",", kind: .punctuation)
                output += "\n"
                advance()
                continue
            }
            guard separator.kind == .arrayEnd else {
                isComplete = false
                return true
            }
            output += "\n"
            indent(depth)
            append("]", kind: .punctuation)
            rootEnd = end(after: separator)
            advance()
            return true
        }
    }

    private var current: Token? {
        position < tokens.count ? tokens[position] : nil
    }

    private mutating func advance() {
        position += 1
    }

    private func end(after token: Token) -> String.Index {
        text.index(token.start, offsetBy: token.text.count)
    }

    private mutating func indent(_ depth: Int) {
        output += String(repeating: " ", count: depth * 2)
    }

    private mutating func append(_ text: String, kind: JSONTokenKind) {
        let location = output.utf16.count
        output += text
        spans.append(FormattedText.Span(kind: kind, range: NSRange(location: location, length: text.utf16.count)))
    }
}
