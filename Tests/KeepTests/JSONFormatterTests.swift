import Foundation
import Testing

@testable import Keep

@Suite("JSON formatting")
struct JSONFormatterTests {
    @Test func nestedValuesKeepTheirInputKeyOrder() throws {
        let formatted = try #require(JSONFormatter.format(#"{"z":1,"a":{"second":true,"first":[]}}"#))
        #expect(formatted.text == "{\n  \"z\": 1,\n  \"a\": {\n    \"second\": true,\n    \"first\": []\n  }\n}")
        let zKey = try #require(formatted.text.range(of: "\"z\"")?.lowerBound)
        #expect(zKey < formatted.text.range(of: "\"a\"")!.lowerBound)
    }

    @Test func stringsKeepEscapesAndUnicode() throws {
        let input = #"{"quote":"she said \"hi\"","emoji":"🌙","accent":"café"}"#
        let formatted = try #require(JSONFormatter.format(input))
        #expect(formatted.text.contains(#""she said \"hi\"""#))
        #expect(formatted.text.contains("🌙"))
        #expect(formatted.text.contains("café"))
    }

    @Test func truncatedValuesKeepTheUnparsedTail() throws {
        let formatted = try #require(JSONFormatter.format(#"{"a":1,"b":oops}"#))
        #expect(formatted.text == "{\n  \"a\": 1,\n  \"b\": oops}")
    }

    @Test func nonJSONTextReturnsNil() {
        #expect(JSONFormatter.format("request failed: timeout") == nil)
    }

    @Test func splitsJSONFromCurlLoggerResponseString() throws {
        let embedded = #"https://api.example.com/v1/items [200] {"response":{"id":42,"ok":true}}"#
        let parts = try #require(JSONFormatter.splitEmbedded(embedded))
        #expect(parts.prefix == "https://api.example.com/v1/items [200] ")
        #expect(parts.json == #"{"response":{"id":42,"ok":true}}"#)
    }

    @Test func spansUseTheFormattedUTF16RangesAndTokenKinds() throws {
        let formatted = try #require(JSONFormatter.format(#"{"café":"🌙","n":12,"ok":false}"#))
        let tokens = formatted.spans.map { span in
            (span.kind, (formatted.text as NSString).substring(with: span.range))
        }
        #expect(tokens.contains { $0.0 == .key && $0.1 == #""café""# })
        #expect(tokens.contains { $0.0 == .string && $0.1 == #""🌙""# })
        #expect(tokens.contains { $0.0 == .number && $0.1 == "12" })
        #expect(tokens.contains { $0.0 == .literal && $0.1 == "false" })
        #expect(tokens.contains { $0.0 == .punctuation && $0.1 == ":" })
        #expect(formatted.spans.allSatisfy { NSMaxRange($0.range) <= (formatted.text as NSString).length })
    }
}
