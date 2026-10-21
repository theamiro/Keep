import Foundation

/// Captures URLSession traffic. Install it on a session configuration with `KeepURLProtocol.install(on:)`.
/// It forwards each request through its own session, so the app sees the same responses and redirects.
///
/// Limits: the forwarding session uses default settings (not the app's custom configuration), background
/// sessions are not captured, and the app's own delegate (for example certificate pinning or auth challenges)
/// does not see the request. For Alamofire, use an `EventMonitor` instead.
public final class KeepURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "com.keep.urlprotocol.handled"

    private var forwarder: URLSession?
    private var forwardingTask: URLSessionDataTask?
    private var receivedResponse: URLResponse?
    /// The first bytes of the response, plus one so the body is still marked as truncated.
    private var receivedBody = Data()
    private var receivedByteCount = 0
    private var startedAt = Date()
    /// Set when a redirect is handed back to the client, which then issues the new request itself.
    private var redirected = false

    public static func install(on configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [KeepURLProtocol.self] + (configuration.protocolClasses ?? [])
    }

    override public class func canInit(with request: URLRequest) -> Bool {
        URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
        startedAt = Date()
        guard let forwardedRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: forwardedRequest)

        let delegate = ForwardingDelegate(
            onRedirect: { [weak self] newRequest, response in
                guard let self else { return }
                redirected = true
                receivedResponse = response
                client?.urlProtocol(self, wasRedirectedTo: newRequest, redirectResponse: response)
                forwardingTask?.cancel()
            },
            onResponse: { [weak self] response in
                self?.receivedResponse = response
                guard let self else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            },
            onData: { [weak self] data in
                guard let self else { return }
                receivedByteCount += data.count
                let room = KeepHTTPTransaction.maximumBodyBytes + 1 - receivedBody.count
                if room > 0 {
                    receivedBody.append(data.prefix(room))
                }
                client?.urlProtocol(self, didLoad: data)
            },
            onComplete: { [weak self] error in
                guard let self else { return }
                if !redirected {
                    if let error {
                        client?.urlProtocol(self, didFailWithError: error)
                    } else {
                        client?.urlProtocolDidFinishLoading(self)
                    }
                }
                recordTransaction(error: redirected ? nil : error)
            }
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        forwarder = session
        forwardingTask = session.dataTask(with: forwardedRequest as URLRequest)
        forwardingTask?.resume()
    }

    override public func stopLoading() {
        forwardingTask?.cancel()
        forwarder?.invalidateAndCancel()
        forwarder = nil
    }

    private func recordTransaction(error: Error?) {
        let httpResponse = receivedResponse as? HTTPURLResponse
        Keep.record(KeepHTTPTransaction(
            id: UUID().uuidString,
            label: "URLSession",
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            requestBody: request.httpBody.map(KeepBody.init),
            statusCode: httpResponse?.statusCode,
            responseHeaders: httpResponse.map { KeepHTTPTransaction.headers(from: $0.allHeaderFields) } ?? [:],
            responseBody: KeepBody(prefix: receivedBody, totalByteCount: receivedByteCount),
            errorDescription: error?.localizedDescription
        ))
    }
}

private final class ForwardingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onRedirect: (URLRequest, URLResponse) -> Void
    private let onResponse: (URLResponse) -> Void
    private let onData: (Data) -> Void
    private let onComplete: (Error?) -> Void

    init(
        onRedirect: @escaping (URLRequest, URLResponse) -> Void,
        onResponse: @escaping (URLResponse) -> Void,
        onData: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.onRedirect = onRedirect
        self.onResponse = onResponse
        self.onData = onData
        self.onComplete = onComplete
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        onRedirect(request, response)
        completionHandler(nil)
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        onResponse(response)
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        onData(data)
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
        session.finishTasksAndInvalidate()
    }
}
