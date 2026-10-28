import Foundation

enum TokenKind {
    case objectStart
    case objectEnd
    case arrayStart
    case arrayEnd
    case colon
    case comma
    case string
    case number
    case literal
}

struct Token {
    let kind: TokenKind
    let text: String
    let start: String.Index
}

struct Lexer {
    let text: String
    private var index: String.Index
    private(set) var failedAt: String.Index?

    init(text: String) {
        self.text = text
        index = text.startIndex
    }

    mutating func tokens() -> [Token] {
        var result: [Token] = []
        while let token = nextToken() {
            result.append(token)
        }
        return result
    }

    // Character classification is deliberately centralized here so the lexer accepts only JSON tokens.
    // swiftlint:disable:next cyclomatic_complexity
    private mutating func nextToken() -> Token? {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex else { return nil }

        let start = index
        let character = text[index]
        let simpleKind: TokenKind?
        switch character {
        case "{": simpleKind = .objectStart
        case "}": simpleKind = .objectEnd
        case "[": simpleKind = .arrayStart
        case "]": simpleKind = .arrayEnd
        case ":": simpleKind = .colon
        case ",": simpleKind = .comma
        default: simpleKind = nil
        }
        if let simpleKind {
            index = text.index(after: index)
            return Token(kind: simpleKind, text: String(character), start: start)
        }

        if character == "\"" {
            return scanString(start: start)
        }
        if character == "-" || isDigit(character) {
            return scanNumber(start: start)
        }
        if character == "t" || character == "f" || character == "n" {
            return scanLiteral(start: start)
        }

        failedAt = start
        return nil
    }

    private mutating func scanString(start: String.Index) -> Token? {
        index = text.index(after: index)
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                index = text.index(after: index)
                return Token(kind: .string, text: String(text[start..<index]), start: start)
            }
            if character.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                failedAt = start
                return nil
            }
            if character == "\\" {
                index = text.index(after: index)
                guard index < text.endIndex else {
                    failedAt = start
                    return nil
                }
            }
            index = text.index(after: index)
        }
        failedAt = start
        return nil
    }

    // The branches mirror the JSON number grammar and keep partial numbers from being accepted.
    // swiftlint:disable:next cyclomatic_complexity
    private mutating func scanNumber(start: String.Index) -> Token? {
        var cursor = index
        if text[cursor] == "-" {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex else {
            failedAt = start
            return nil
        }

        if text[cursor] == "0" {
            cursor = text.index(after: cursor)
        } else if isDigit(text[cursor]), text[cursor] != "0" {
            repeat {
                cursor = text.index(after: cursor)
            } while cursor < text.endIndex && isDigit(text[cursor])
        } else {
            failedAt = start
            return nil
        }

        if cursor < text.endIndex, text[cursor] == "." {
            cursor = text.index(after: cursor)
            guard cursor < text.endIndex, isDigit(text[cursor]) else {
                failedAt = start
                return nil
            }
            repeat {
                cursor = text.index(after: cursor)
            } while cursor < text.endIndex && isDigit(text[cursor])
        }

        if cursor < text.endIndex, text[cursor] == "e" || text[cursor] == "E" {
            cursor = text.index(after: cursor)
            if cursor < text.endIndex, text[cursor] == "+" || text[cursor] == "-" {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex, isDigit(text[cursor]) else {
                failedAt = start
                return nil
            }
            repeat {
                cursor = text.index(after: cursor)
            } while cursor < text.endIndex && isDigit(text[cursor])
        }

        if cursor < text.endIndex, !isDelimiter(text[cursor]) {
            failedAt = start
            return nil
        }
        index = cursor
        return Token(kind: .number, text: String(text[start..<cursor]), start: start)
    }

    private mutating func scanLiteral(start: String.Index) -> Token? {
        let literal: String
        switch text[index] {
        case "t": literal = "true"
        case "f": literal = "false"
        default: literal = "null"
        }
        guard text[index...].hasPrefix(literal) else {
            failedAt = start
            return nil
        }
        let end = text.index(index, offsetBy: literal.count)
        guard end == text.endIndex || isDelimiter(text[end]) else {
            failedAt = start
            return nil
        }
        index = end
        return Token(kind: .literal, text: literal, start: start)
    }

    private func isDelimiter(_ character: Character) -> Bool {
        character.isWhitespace || "{}[]:,".contains(character)
    }

    private func isDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        return (48...57).contains(scalar.value)
    }
}
