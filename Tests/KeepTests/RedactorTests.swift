import Foundation
import Testing

@testable import Keep

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

    @Test func accessAndRefreshTokensInFreeTextAreRedacted() {
        let output = redactor.redact(message: "Refresh failed access_token=abc123 refresh_token=def456 retry=2")
        #expect(!output.contains("abc123"))
        #expect(!output.contains("def456"))
        #expect(output.contains("retry=2"))
    }

    @Test func clientSecretInFormBodyIsRedactedAndOtherPairsKept() {
        let output = redactor.redact(
            body: "grant_type=refresh_token&client_id=app&client_secret=s3cr3t&refresh_token=r3fr35h")
        #expect(!output.contains("s3cr3t"))
        #expect(!output.contains("r3fr35h"))
        #expect(output.contains("client_id=app"))
    }

    @Test func bracketedFormKeysAreRedacted() {
        let output = redactor.redact(body: "user[password]=hunter2&user[name]=ann")
        #expect(!output.contains("hunter2"))
        #expect(output.contains("user[name]=ann"))
    }

    @Test func jsonPairsInsideMessagesAreRedacted() {
        let output = redactor.redact(message: #"Sent {"password": "hunter2"} and {"token":"x"} ok"#)
        #expect(!output.contains("hunter2"))
        #expect(!output.contains("\"x\""))
        #expect(output.contains("ok"))
    }

    @Test func escapedJSONPairsInsideMessagesAreRedacted() {
        let output = redactor.redact(message: #"body {\"password\": \"hunter2\"} sent"#)
        #expect(!output.contains("hunter2"))
    }

    @Test func secretBeforeTheBodyCutIsRedactedWhenTheJSONNoLongerParses() {
        let padding = String(repeating: "a", count: KeepHTTPTransaction.maximumBodyBytes)
        let body = KeepBody(Data(#"{"password":"hunter2","note":"\#(padding)"}"#.utf8))
        #expect(body.isTruncated)
        let output = body.redacted(redactor)
        #expect(!output.text.contains("hunter2"))
        #expect(output.text.contains("[REDACTED]"))
    }

    @Test func fragmentTokensInURLsAreRedacted() {
        let output = redactor.redact(url: "https://app.example.com/callback#access_token=opaque123&expires_in=3600")
        #expect(!output.contains("opaque123"))
        #expect(output.contains("expires_in=3600"))
    }

    @Test func signedURLParametersAreRedacted() {
        let output = redactor.redact(url: "https://s3.example.com/object?X-Amz-Signature=abcdef&X-Amz-Date=20260101")
        #expect(!output.contains("abcdef"))
        #expect(output.contains("X-Amz-Date=20260101"))
    }

    @Test func signatureSessionAndSidKeysAreSensitive() {
        #expect(redactor.isSensitive(key: "X-Amz-Signature"))
        #expect(redactor.isSensitive(key: "sessionId"))
        #expect(redactor.isSensitive(key: "sid"))
        #expect(!redactor.isSensitive(key: "sidebar"))
    }

    @Test func customPatternsThatDoNotCompileAreReportedAndSkipped() {
        var policy = KeepRedactionPolicy()
        policy.extraPatterns = ["([unclosed", "ORDER-\\d+"]
        let custom = Redactor(policy: policy)
        #expect(custom.rejectedPatterns == ["([unclosed"])
        #expect(!custom.redact(message: "shipped ORDER-4421").contains("4421"))
    }

    @Test func rejectedCustomPatternIsRecordedAsCriticalEntryAtStart() throws {
        var configuration = makeConfiguration()
        configuration.redaction.extraPatterns = ["([unclosed"]
        let core = makeCore(configuration, directory: try makeTemporaryDirectory())
        let entry = try #require(core.logs.snapshot().first)
        #expect(entry.level == .critical)
        #expect(entry.label == "Keep")
        #expect(entry.message.contains("([unclosed"))
    }

    @Test func repeatedPatternShapesDoNotStallRedaction() {
        let shapes = [
            String(repeating: "eyJ-", count: 25_000),
            String(repeating: "a@", count: 50_000),
            String(repeating: "a.", count: 50_000),
            String(repeating: "bearer ", count: 14_000)
        ]
        for shape in shapes {
            let elapsed = Self.seconds { _ = redactor.redact(message: shape) }
            #expect(elapsed < 1, "redaction of a \(shape.prefix(8))… shape took \(elapsed) s")
        }
    }

    @Test func longAlphanumericRunStillRedactsQuicklyAndFindsEmails() {
        let run = String(repeating: "aB3", count: 33_334)
        var output = ""
        let elapsed = Self.seconds {
            output = redactor.redact(message: run + " john.doe@example.com")
        }
        #expect(!output.contains("john.doe"))
        #expect(elapsed < 1, "redaction took \(elapsed) s")
    }

    /// How long `body` takes, in seconds. `ContinuousClock` needs iOS 16, and Keep supports iOS 15.
    private static func seconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }
}
