import Foundation

/// A captured request and its response or error (see "Network transaction" in CONTEXT.md).
/// Build one from any HTTP client (URLSession, Alamofire) and pass it to `Keep.record`.
public struct KeepHTTPTransaction: Codable, Hashable, Identifiable, Sendable {
    /// Bodies are kept up to this many bytes; the rest is dropped and marked as truncated.
    public static let maximumBodyBytes = 256 * 1024

    public let id: String
    /// Which client made the request, e.g. "URLSession" or "Alamofire".
    public let label: String
    public let startedAt: Date
    public let duration: TimeInterval
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]
    public let requestBody: KeepBody?
    public let statusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: KeepBody?
    public let errorDescription: String?

    public init(
        label: String,
        startedAt: Date,
        duration: TimeInterval,
        request: URLRequest,
        response: URLResponse?,
        requestBody: Data? = nil,
        responseBody: Data? = nil,
        error: Error? = nil
    ) {
        let httpResponse = response as? HTTPURLResponse
        id = UUID().uuidString
        self.label = label
        self.startedAt = startedAt
        self.duration = duration
        method = request.httpMethod ?? "GET"
        url = request.url?.absoluteString ?? ""
        requestHeaders = request.allHTTPHeaderFields ?? [:]
        self.requestBody = (requestBody ?? request.httpBody).map(KeepBody.init)
        statusCode = httpResponse?.statusCode
        responseHeaders = httpResponse.map { Self.headers(from: $0.allHeaderFields) } ?? [:]
        self.responseBody = responseBody.map(KeepBody.init)
        errorDescription = error?.localizedDescription
    }

    /// Used by the redactor to build a copy with sensitive parts replaced.
    init(copying transaction: KeepHTTPTransaction, url: String, requestHeaders: [String: String],
         requestBody: KeepBody?, responseHeaders: [String: String], responseBody: KeepBody?) {
        id = transaction.id
        label = transaction.label
        startedAt = transaction.startedAt
        duration = transaction.duration
        method = transaction.method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        statusCode = transaction.statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        errorDescription = transaction.errorDescription
    }

    /// A copy of this transaction with the given redacted parts.
    func redacted(_ redactor: Redactor) -> KeepHTTPTransaction {
        KeepHTTPTransaction(
            copying: self,
            url: redactor.redact(url: url),
            requestHeaders: redactor.redact(headers: requestHeaders),
            requestBody: requestBody.map { $0.redacted(redactor) },
            responseHeaders: redactor.redact(headers: responseHeaders),
            responseBody: responseBody.map { $0.redacted(redactor) }
        )
    }

    /// A single-line curl command that reproduces the request. Values are already redacted.
    public var curlCommand: String {
        var parts = ["curl", "-X", method, Self.shellQuoted(url)]
        for (name, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            parts += ["-H", Self.shellQuoted("\(name): \(value)")]
        }
        if let body = requestBody, !body.text.isEmpty {
            parts += ["--data-binary", Self.shellQuoted(body.text)]
        }
        return parts.joined(separator: " ")
    }

    /// Path plus query, for compact list rows.
    public var displayPath: String {
        guard let components = URLComponents(string: url) else { return url }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return components.percentEncodedQuery.map { "\(path)?\($0)" } ?? path
    }

    static func headers(from fields: [AnyHashable: Any]) -> [String: String] {
        fields.reduce(into: [:]) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// A request or response body, truncated and decoded as text. Binary bodies are summarised.
public struct KeepBody: Codable, Hashable, Sendable {
    public let text: String
    public let byteCount: Int
    public let isTruncated: Bool

    public init(_ data: Data) {
        byteCount = data.count
        isTruncated = data.count > KeepHTTPTransaction.maximumBodyBytes
        let kept = isTruncated ? data.prefix(KeepHTTPTransaction.maximumBodyBytes) : data[...]
        if let text = String(data: kept, encoding: .utf8) {
            self.text = text
        } else if isTruncated {
            text = String(decoding: kept, as: UTF8.self)
        } else {
            text = "<binary \(data.count) bytes>"
        }
    }

    init(text: String, byteCount: Int, isTruncated: Bool) {
        self.text = text
        self.byteCount = byteCount
        self.isTruncated = isTruncated
    }

    func redacted(_ redactor: Redactor) -> KeepBody {
        KeepBody(text: redactor.redact(body: text), byteCount: byteCount, isTruncated: isTruncated)
    }
}
