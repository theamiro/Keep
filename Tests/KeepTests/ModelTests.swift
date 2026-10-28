import Foundation
import Logging
import Testing

@testable import Keep

@Suite("Model and tagging")
struct ModelTests {
    @Test func metadataConvertsToJSONValues() {
        let metadata: Logger.Metadata = [
            "a": "x",
            "b": .dictionary(["c": "y"]),
            "d": .array(["z"]),
            "e": .stringConvertible(42)
        ]
        let json = JSONValue(metadata: metadata)
        #expect(
            json
                == .object([
                    "a": .string("x"),
                    "b": .object(["c": .string("y")]),
                    "d": .array([.string("z")]),
                    "e": .string("42")
                ]))
    }

    @Test func jsonValuesRoundTripThroughCodable() throws {
        let value: JSONValue = .object(["k": .array([.string("v"), .object([:])])])
        let data = try KeepCodec.encoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test func logEntriesRoundTripThroughJSONLines() throws {
        let entry = LogEntry(
            sequence: 7, timestamp: Date(timeIntervalSince1970: 1_700_000_000.123), level: .warning,
            label: "net", message: "slow", metadata: ["ms": .string("900")], source: "Net",
            file: "Client.swift", function: "send()", line: 9, tag: "HTTP"
        )
        let data = try KeepCodec.encoder().encode(entry)
        let decoded = try KeepCodec.decoder().decode(LogEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test func tagRulesMatchTheirSignalsOnly() {
        let rules = KeepTagRule.defaults
        #expect(KeepTagRule.title(for: "curl -X GET x", metadataKeys: [], rules: rules) == "HTTP")
        #expect(KeepTagRule.title(for: "Loaded", metadataKeys: ["url"], rules: rules) == "HTTP")
        #expect(KeepTagRule.title(for: "Loaded", metadataKeys: ["http.status"], rules: rules) == "HTTP")
        #expect(KeepTagRule.title(for: "Thing deinit", metadataKeys: [], rules: rules) == "Memory")
        #expect(KeepTagRule.title(for: "Initial state", metadataKeys: [], rules: rules) == "Unknown")
        #expect(KeepTagRule.title(for: "Fetched", metadataKeys: ["status"], rules: rules) == "Unknown")
    }

    @Test func customTagRulesTakePrecedenceInOrder() {
        let rules =
            [KeepTagRule(title: "Checkout") { message, _ in message.hasPrefix("checkout") }] + KeepTagRule.defaults
        #expect(KeepTagRule.title(for: "checkout failed", metadataKeys: [], rules: rules) == "Checkout")
    }
}
