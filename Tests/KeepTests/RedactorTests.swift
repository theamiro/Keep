import Foundation
@testable import Keep
import Testing

@Suite("Redaction")
struct RedactorTests {
    private let redactor = Redactor(policy: KeepRedactionPolicy())

    @Test func bearerTokensInMessagesAreRemovedAndSchemeKept() {
        let output = redactor.redact(message: "Authorization: Bearer abc.def-123 sent")
        #expect(!output.contains("abc.def"))
        #expect(output.contains("[REDACTED]"))
    }

    @Test func curlAuthorizationHeaderIsRedacted() {
        let output = redactor.redact(message: "curl -H 'Authorization: Bearer sk_live_999' https://api.example.com")
        #expect(!output.contains("sk_live_999"))
        #expect(output.contains("https://api.example.com"))
    }

    @Test func jwtsAreRemoved() {
        let output = redactor.redact(message: "session eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl done")
        #expect(!output.contains("eyJhbGci"))
    }

    @Test func emailsPhonesAndSSNsAreRemoved() {
        let output = redactor.redact(message: "user john.doe@example.com phone +254712345678 ssn 123-45-6789")
        #expect(!output.contains("john.doe"))
        #expect(!output.contains("+254712345678"))
        #expect(!output.contains("123-45-6789"))
    }

    @Test func cardNumbersAreRedactedOnlyWhenLuhnValid() {
        let valid = redactor.redact(message: "card 4111 1111 1111 1111 declined")
        #expect(!valid.contains("4111"))
        let invalid = redactor.redact(message: "order 4111 1111 1111 1112 placed")
        #expect(invalid.contains("4111 1111 1111 1112"))
    }

    @Test func luhnCheckMatchesKnownNumbers() {
        #expect(Redactor.isLuhnValid("4111111111111111"))
        #expect(!Redactor.isLuhnValid("4111111111111112"))
        #expect(!Redactor.isLuhnValid("12345"))
    }

    @Test func sensitiveMetadataKeysAreRedactedByToken() {
        let metadata: [String: JSONValue] = [
            "token": .string("t1"),
            "authorization_token": .string("t2"),
            "apiKey": .string("t3"),
            "X-Api-Key": .string("t4"),
            "accessToken": .string("t5"),
            "author": .string("Ann"),
            "status": .string("200")
        ]
        let output = redactor.redact(metadata: metadata)
        for key in ["token", "authorization_token", "apiKey", "X-Api-Key", "accessToken"] {
            #expect(output[key] == .string("[REDACTED]"), "\(key) should be redacted")
        }
        #expect(output["author"] == .string("Ann"))
        #expect(output["status"] == .string("200"))
    }

    @Test func allowedKeysAreLeftUntouched() {
        var policy = KeepRedactionPolicy()
        policy.allowedKeys = ["token"]
        let output = Redactor(policy: policy).redact(metadata: ["token": .string("visible")])
        #expect(output["token"] == .string("visible"))
    }

    @Test func extraKeysAndPatternsAreRedacted() {
        var policy = KeepRedactionPolicy()
        policy.extraKeys = ["customerRef"]
        policy.extraPatterns = ["ORDER-\\d+", "([unclosed"]
        let custom = Redactor(policy: policy)
        #expect(custom.redact(metadata: ["customerRef": .string("c-1")])["customerRef"] == .string("[REDACTED]"))
        #expect(!custom.redact(message: "shipped ORDER-4421").contains("4421"))
    }

    @Test func tokenizationSplitsSeparatorsAndCamelCase() {
        #expect(Redactor.tokens(of: "authorization_token") == ["authorization", "token"])
        #expect(Redactor.tokens(of: "apiKey") == ["api", "key"])
        #expect(Redactor.tokens(of: "X-Api-Key") == ["x", "api", "key"])
        #expect(Redactor.tokens(of: "author") == ["author"])
    }

    @Test func sensitiveHeadersAreRedactedAndOthersKept() {
        let output = redactor.redact(headers: [
            "Authorization": "Bearer abc",
            "Cookie": "session=xyz",
            "Accept": "application/json"
        ])
        #expect(output["Authorization"] == "[REDACTED]")
        #expect(output["Cookie"] == "[REDACTED]")
        #expect(output["Accept"] == "application/json")
    }

    @Test func urlCredentialsAndSensitiveQueryValuesAreRedacted() {
        let output = redactor.redact(url: "https://user:pass@api.example.com/v1/items?token=abc&page=2")
        #expect(!output.contains("pass"))
        #expect(!output.contains("abc"))
        #expect(output.contains("page=2"))
        #expect(output.contains("REDACTED"))
    }

    @Test func jsonBodiesRedactNestedSensitiveKeys() {
        let output = redactor.redact(body: #"{"password":"hunter2","profile":{"email":"a@b.com","name":"Ann"}}"#)
        #expect(!output.contains("hunter2"))
        #expect(!output.contains("a@b.com"))
        #expect(output.contains("Ann"))
        #expect(output.contains("[REDACTED]"))
    }

    @Test func nonJSONBodiesGetThePatternPass() {
        let output = redactor.redact(body: "password=hunter2&user=ann")
        #expect(!output.contains("hunter2"))
        #expect(output.contains("user=ann"))
    }
}
