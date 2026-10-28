import Foundation
import Testing

@testable import Keep

@Suite("Network transactions")
struct NetworkTransactionTests {
    private func makeTransaction(body: Data? = Data(#"{"a":1}"#.utf8)) throws -> KeepHTTPTransaction {
        var request = try URLRequest(url: #require(URL(string: "https://api.example.com/v1/items?limit=6")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let response = try #require(
            HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: ["X-Trace": "1"]
            ))
        return KeepHTTPTransaction(
            label: "URLSession",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 0.25,
            request: request,
            response: response,
            responseBody: Data(#"{"ok":true}"#.utf8)
        )
    }

    @Test func builtFromURLRequestAndResponse() throws {
        let transaction = try makeTransaction()
        #expect(transaction.method == "POST")
        #expect(transaction.statusCode == 201)
        #expect(transaction.requestHeaders["Content-Type"] == "application/json")
        #expect(transaction.responseHeaders["X-Trace"] == "1")
        #expect(transaction.requestBody?.text == #"{"a":1}"#)
        #expect(transaction.responseBody?.text == #"{"ok":true}"#)
        #expect(transaction.displayPath == "/v1/items?limit=6")
    }

    @Test func curlCommandReproducesTheRequest() throws {
        let transaction = try makeTransaction()
        #expect(
            transaction.curlCommand
                == #"curl -X POST 'https://api.example.com/v1/items?limit=6' -H 'Content-Type: application/json' --data-binary '{"a":1}'"#
        )
    }

    @Test func singleQuotesAreShellEscaped() {
        #expect(KeepHTTPTransaction.shellQuoted("it's") == "'it'\\''s'")
    }

    @Test func largeBodiesAreTruncatedAndBinaryBodiesSummarised() {
        let large = KeepBody(Data(repeating: 0x61, count: KeepHTTPTransaction.maximumBodyBytes + 100))
        #expect(large.isTruncated)
        #expect(large.byteCount == KeepHTTPTransaction.maximumBodyBytes + 100)
        #expect(large.text.utf8.count == KeepHTTPTransaction.maximumBodyBytes)

        let binary = KeepBody(Data([0xFF, 0xFE, 0x00]))
        #expect(binary.text == "<binary 3 bytes>")
        #expect(!binary.isTruncated)
    }

    @Test func recordedTransactionsAreRedactedAndStored() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        var request = try URLRequest(url: #require(URL(string: "https://api.example.com/login?token=abc")))
        request.setValue("Bearer live-token-42", forHTTPHeaderField: "Authorization")
        core.record(
            KeepHTTPTransaction(
                label: "URLSession", startedAt: Date(), duration: 0.1, request: request, response: nil,
                error: URLError(.timedOut)
            ))
        core.drainQueue()

        let stored = try #require(core.transactions.snapshot().first)
        #expect(stored.requestHeaders["Authorization"] == "[REDACTED]")
        #expect(!stored.url.contains("abc"))
        #expect(stored.errorDescription != nil)
    }

    @Test func errorDescriptionsAreRedactedBeforeTheyAreKept() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        let request = try URLRequest(url: #require(URL(string: "https://api.example.com/refresh")))
        let error = NSError(
            domain: "Refresh", code: 401,
            userInfo: [
                NSLocalizedDescriptionKey: "Refresh failed for jane@example.com with token=abc123"
            ])
        core.record(
            KeepHTTPTransaction(
                label: "URLSession", startedAt: Date(), duration: 0.1, request: request, response: nil, error: error
            ))
        core.drainQueue()

        let stored = try #require(core.transactions.snapshot().first)
        let description = try #require(stored.errorDescription)
        #expect(!description.contains("jane@example.com"))
        #expect(!description.contains("abc123"))
    }

    @Test func streamedBodiesKeepTheirTotalSizeAndOnlyTheFirstBytes() {
        let prefix = Data(repeating: 0x61, count: KeepHTTPTransaction.maximumBodyBytes + 1)
        let body = KeepBody(prefix: prefix, totalByteCount: 5_000_000)
        #expect(body.isTruncated)
        #expect(body.byteCount == 5_000_000)
        #expect(body.text.utf8.count == KeepHTTPTransaction.maximumBodyBytes)
    }

    @Test func harOutputFollowsTheHARShape() throws {
        let data = try HAR.data(for: [makeTransaction()], creatorVersion: "0.1.0")
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let log = try #require(root["log"] as? [String: Any])
        #expect(log["version"] as? String == "1.2")
        #expect((log["creator"] as? [String: Any])?["name"] as? String == "Keep")
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let request = try #require(entry["request"] as? [String: Any])
        let response = try #require(entry["response"] as? [String: Any])
        #expect(request["method"] as? String == "POST")
        #expect(response["status"] as? Int == 201)
        #expect(entry["time"] as? Double == 250)
    }
}

/// Runs with the shared runtime, so it is the only test that installs a core into it.
@Suite("URLSession capture", .serialized)
struct URLProtocolCaptureTests {
    @Test func failedRequestsAreForwardedAndRecorded() async throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        #expect(KeepRuntime.shared.install(core))

        let configuration = URLSessionConfiguration.ephemeral
        KeepURLProtocol.install(on: configuration)
        let session = URLSession(configuration: configuration)
        // Port 9 on loopback refuses the connection, so the request fails without touching the network.
        let url = try #require(URL(string: "http://127.0.0.1:9/items?token=abc"))

        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: url)
        }

        var recorded: [KeepHTTPTransaction] = []
        for _ in 0..<40 where recorded.isEmpty {
            core.drainQueue()
            recorded = core.transactions.snapshot()
            if recorded.isEmpty {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        let transaction = try #require(recorded.first)
        #expect(transaction.label == "URLSession")
        #expect(transaction.errorDescription != nil)
        #expect(!transaction.url.contains("abc"))
    }
}
