import Foundation
import Network
import Testing

@testable import Keep

/// Runs with the shared runtime. The runtime is process-wide, so this suite installs one core for all its tests and
/// tells them apart by URL path. It is the only suite that installs a core into the runtime.
@Suite("URLSession capture", .serialized)
struct URLProtocolCaptureTests {
    private static let core: KeepCore = {
        let directory = (try? makeTemporaryDirectory()) ?? FileManager.default.temporaryDirectory
        let core = makeCore(directory: directory)
        precondition(KeepRuntime.shared.install(core), "another core is already installed")
        return core
    }()

    private static let server: LoopbackServer = {
        guard let server = try? LoopbackServer.start() else {
            preconditionFailure("the loopback server did not start")
        }
        return server
    }()

    private struct NoTransaction: Error {
        let path: String
    }

    /// A session like the app's: Keep's protocol installed first, as the sample app does. Touching `core` first means
    /// the runtime holds a core before the request starts, as it does in an app that has called `Keep.start`.
    private func makeAppSession() -> URLSession {
        _ = Self.core
        let configuration = URLSessionConfiguration.ephemeral
        KeepURLProtocol.install(on: configuration)
        return URLSession(configuration: configuration)
    }

    private func url(_ path: String) throws -> URL {
        try #require(URL(string: "http://127.0.0.1:\(Self.server.port)\(path)"))
    }

    /// Waits for the transaction recorded for `path`, since capture runs on Keep's queue.
    private func recordedTransaction(path: String) async throws -> KeepHTTPTransaction {
        for _ in 0..<40 {
            Self.core.drainQueue()
            let found = Self.core.transactions.snapshot().first { URL(string: $0.url)?.path == path }
            if let found {
                return found
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NoTransaction(path: path)
    }

    @Test func failedRequestsAreForwardedAndRecorded() async throws {
        _ = Self.core
        let configuration = URLSessionConfiguration.ephemeral
        KeepURLProtocol.install(on: configuration)
        let session = URLSession(configuration: configuration)
        // Port 9 on loopback refuses the connection, so the request fails without touching the network.
        let url = try #require(URL(string: "http://127.0.0.1:9/items?token=abc"))

        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: url)
        }

        let transaction = try await recordedTransaction(path: "/items")
        #expect(transaction.label == "URLSession")
        #expect(transaction.errorDescription != nil)
        #expect(!transaction.url.contains("abc"))
    }

    @Test func successfulGETReturnsTheResponseAndRecordsIt() async throws {
        let (data, response) = try await makeAppSession().data(from: try url("/get"))

        #expect(utf8(data) == "hello")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let transaction = try await recordedTransaction(path: "/get")
        #expect(transaction.method == "GET")
        #expect(transaction.statusCode == 200)
        #expect(transaction.responseBody?.text == "hello")
    }

    @Test func postBodiesSentAsStreamsReachTheServerAndAreRecorded() async throws {
        let payload = #"{"item":"A-1","quantity":2}"#
        var request = URLRequest(url: try url("/echo"))
        request.httpMethod = "POST"
        // URLSession hands a stream body to the protocol with `httpBody` nil, which is the case this test covers.
        request.httpBodyStream = InputStream(data: Data(payload.utf8))

        let (data, _) = try await makeAppSession().data(for: request)

        #expect(utf8(data) == payload)
        let transaction = try await recordedTransaction(path: "/echo")
        #expect(transaction.method == "POST")
        // Recorded JSON bodies are re-serialised by redaction, so compare the content rather than the bytes.
        let recorded = try #require(transaction.requestBody?.text)
        let object = try JSONSerialization.jsonObject(with: Data(recorded.utf8)) as? [String: Any]
        #expect(object?["item"] as? String == "A-1")
        #expect(object?["quantity"] as? Int == 2)
    }

    @Test func redirectsAreFollowedAndEachHopIsRecorded() async throws {
        let (data, _) = try await makeAppSession().data(from: try url("/redirect"))

        #expect(utf8(data) == "hello")
        let redirect = try await recordedTransaction(path: "/redirect")
        #expect(redirect.statusCode == 302)
        let final = try await recordedTransaction(path: "/final")
        #expect(final.statusCode == 200)
    }

    /// The forwarding session must not write responses to the shared URL cache, which is on disk. A cacheable answer
    /// that goes through Keep must leave the cache's disk use unchanged.
    @Test func forwardedResponsesDoNotGrowTheSharedURLCache() async throws {
        let session = makeAppSession()
        try await Task.sleep(nanoseconds: 200_000_000)
        let before = URLCache.shared.currentDiskUsage

        _ = try await session.data(from: try url("/counter-\(UUID().uuidString)"))

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(URLCache.shared.currentDiskUsage == before)
    }

    /// The server counts hits per path and marks its answers cacheable. Two requests that both reach the server show
    /// that nothing answered the second one from a cache.
    @Test func repeatedGETsReachTheServerEveryTime() async throws {
        let path = "/counter-\(UUID().uuidString)"
        let session = makeAppSession()
        let first = try await session.data(from: try url(path)).0
        let second = try await session.data(from: try url(path)).0

        #expect(utf8(first) == "1")
        #expect(utf8(second) == "2")
    }

    @Test func aDisabledCoreOrAnotherSchemeIsNotIntercepted() throws {
        let disabled = makeCore(makeConfiguration(.appStore), directory: try makeTemporaryDirectory())
        #expect(!disabled.isEnabled)
        let request = URLRequest(url: try url("/get"))

        #expect(!KeepURLProtocol.shouldIntercept(request, using: disabled))
        #expect(!KeepURLProtocol.shouldIntercept(request, using: nil))
        #expect(!KeepURLProtocol.shouldIntercept(URLRequest(url: URL(fileURLWithPath: "/tmp/file")), using: Self.core))
        #expect(KeepURLProtocol.shouldIntercept(request, using: Self.core))
    }
}

/// The UTF-8 text of `data`, or an empty string when it is not UTF-8.
private func utf8(_ data: some DataProtocol) -> String {
    String(data: Data(data), encoding: .utf8) ?? ""
}

/// A minimal HTTP/1.1 server on loopback for the forwarding tests. It answers one request per connection, then
/// closes it, and understands `Content-Length` and chunked request bodies.
private final class LoopbackServer: @unchecked Sendable {
    /// Set once, by `start`, before any test reads it.
    private(set) var port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.keep.tests.loopback")
    /// Hits per path, for the caching tests. Only touched on `queue`.
    private var hits: [String: Int] = [:]

    private struct Reply {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    private init(listener: NWListener) {
        self.listener = listener
        port = 0
    }

    static func start() throws -> LoopbackServer {
        let listener = try NWListener(using: .tcp)
        let server = LoopbackServer(listener: listener)
        // The handler must be set before the listener starts, and the port is known only once it is ready.
        listener.newConnectionHandler = { connection in
            server.handle(connection)
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.signal()
            }
        }
        listener.start(queue: server.queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
        server.port = port
        return server
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffered: Data())
    }

    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            var buffered = buffered
            if let data {
                buffered.append(data)
            }
            if let request = HTTPRequest(parsing: buffered) {
                respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffered: buffered)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let reply = reply(for: request)
        var head = "HTTP/1.1 \(reply.status) \(Self.reason(for: reply.status))\r\n"
        head += "Content-Length: \(reply.body.count)\r\nConnection: close\r\n"
        for (name, value) in reply.headers {
            head += "\(name): \(value)\r\n"
        }
        var bytes = Data((head + "\r\n").utf8)
        bytes.append(reply.body)
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func reply(for request: HTTPRequest) -> Reply {
        if request.path.hasPrefix("/counter-") {
            let count = hits[request.path, default: 0] + 1
            hits[request.path] = count
            return Reply(status: 200, headers: ["Cache-Control": "max-age=60"], body: Data("\(count)".utf8))
        }
        switch request.path {
        case "/get", "/final":
            return Reply(status: 200, headers: ["Content-Type": "text/plain"], body: Data("hello".utf8))
        case "/redirect":
            return Reply(status: 302, headers: ["Location": "/final"], body: Data())
        case "/echo":
            return Reply(status: 200, headers: ["Content-Type": "application/json"], body: request.body)
        default:
            return Reply(status: 404, headers: [:], body: Data())
        }
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 302: return "Found"
        default: return "Not Found"
        }
    }
}

private struct HTTPRequest {
    let path: String
    let body: Data

    /// Nil until the whole request has arrived.
    init?(parsing data: Data) {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = utf8(data[..<separator.lowerBound]).components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        path = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let rest = Data(data[separator.upperBound...])
        if headers["transfer-encoding"]?.lowercased() == "chunked" {
            guard let decoded = Self.dechunk(rest) else { return nil }
            body = decoded
        } else {
            let length = Int(headers["content-length"] ?? "") ?? 0
            guard rest.count >= length else { return nil }
            body = rest.prefix(length)
        }
    }

    /// The payload of a chunked body, or nil while more chunks are needed.
    private static func dechunk(_ data: Data) -> Data? {
        let crlf = Data("\r\n".utf8)
        var payload = Data()
        var cursor = data.startIndex
        while true {
            guard let lineEnd = data[cursor...].range(of: crlf) else { return nil }
            let sizeText = utf8(data[cursor..<lineEnd.lowerBound])
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { return nil }
            cursor = lineEnd.upperBound
            if size == 0 {
                return data.distance(from: cursor, to: data.endIndex) >= crlf.count ? payload : nil
            }
            guard data.distance(from: cursor, to: data.endIndex) >= size + crlf.count else { return nil }
            payload.append(data[cursor..<data.index(cursor, offsetBy: size)])
            cursor = data.index(cursor, offsetBy: size + crlf.count)
        }
    }
}
