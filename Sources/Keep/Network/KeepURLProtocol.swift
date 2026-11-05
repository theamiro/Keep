import Foundation

/// Captures URLSession traffic. Install it on a session configuration with `KeepURLProtocol.install(on:)`.
/// It forwards each request through its own session, so the app sees the same responses and redirects.
///
/// Limits: the forwarding session uses default settings (not the app's custom configuration) and no URL cache.
/// Background sessions are not captured, and the app's own delegate (for example certificate pinning or auth
/// challenges) does not see the request. For Alamofire, use an `EventMonitor` instead.
public final class KeepURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "com.keep.urlprotocol.handled"

    private var forwarder: URLSession?
    private var forwardingTask: URLSessionDataTask?
    /// One serial queue carries the forwarding delegate's callbacks and `stopLoading`. The state below is only touched
    /// there, after `startLoading` has started the task.
    private let forwardingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.keep.urlprotocol.forwarding"
        return queue
    }()
    private var startedAt = Date()
    /// The request body as the app sent it. A stream body is read once, so this is the only copy Keep has.
    private var requestBody: Data?
    private var receivedResponse: URLResponse?
    /// The first bytes of the response, plus one so the body is still marked as truncated.
    private var receivedBody = Data()
    private var receivedByteCount = 0
    /// Set when a redirect is handed back to the client, which then issues the new request itself.
    private var redirected = false

    public static func install(on configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [KeepURLProtocol.self] + (configuration.protocolClasses ?? [])
    }

    override public class func canInit(with request: URLRequest) -> Bool {
        shouldIntercept(request, using: KeepRuntime.shared.current)
    }

    /// Whether Keep takes `request`. Only a running core takes it, and only web requests that the app has not already
    /// handed to the forwarding session. Anything else goes to the network exactly as it would without Keep.
    static func shouldIntercept(_ request: URLRequest, using core: KeepCore?) -> Bool {
        guard let core, core.isEnabled else { return false }
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return URLProtocol.property(forKey: handledKey, in: request) == nil
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

        // URLSession gives a stream body to the protocol with `httpBody` nil. The whole body is read, so the forwarded
        // request sends what the app sent, and the copy is kept for the transaction.
        let body = forwardedRequest.httpBody ?? forwardedRequest.httpBodyStream.map(Self.readAll)
        requestBody = body
        if let body {
            // Clear the stream first: clearing it discards a body that is already set.
            forwardedRequest.httpBodyStream = nil
            forwardedRequest.httpBody = body
        }

        let session = URLSession(
            configuration: Self.makeForwardingConfiguration(),
            delegate: makeForwardingDelegate(),
            delegateQueue: forwardingQueue
        )
        forwarder = session
        forwardingTask = session.dataTask(with: forwardedRequest as URLRequest)
        forwardingTask?.resume()
    }

    /// Passes the forwarding session's callbacks on to the app's session, and records the transaction when it ends.
    ///
    /// The closures hold this instance strongly. The app's session can release the instance when a redirect is handed
    /// back or the request is stopped, and a weak reference then dropped the transaction of the forwarded request whose
    /// completion arrived later. Every path invalidates the forwarding session, which releases the delegate, so the
    /// reference does not outlive the request.
    private func makeForwardingDelegate() -> ForwardingDelegate {
        ForwardingDelegate(
            onRedirect: { [self] newRequest, response in
                redirected = true
                receivedResponse = response
                client?.urlProtocol(self, wasRedirectedTo: Self.nextHop(from: newRequest), redirectResponse: response)
                forwardingTask?.cancel()
            },
            onResponse: { [self] response in
                receivedResponse = response
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            },
            onData: { [self] data in
                receivedByteCount += data.count
                let room = KeepHTTPTransaction.maximumBodyBytes + 1 - receivedBody.count
                if room > 0 {
                    receivedBody.append(data.prefix(room))
                }
                client?.urlProtocol(self, didLoad: data)
            },
            onComplete: { [self] error in
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
    }

    override public func stopLoading() {
        forwardingQueue.addOperation {
            self.forwardingTask?.cancel()
            self.forwarder?.invalidateAndCancel()
            self.forwarder = nil
        }
    }

    /// The forwarding session keeps no URL cache. The shared cache is on disk, and Keep keeps nothing on disk.
    private static func makeForwardingConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        return configuration
    }

    /// The redirected request is a copy of the forwarded one, so it carries the loop guard. Remove the guard, so the
    /// app's session hands the next hop to Keep too.
    private static func nextHop(from request: URLRequest) -> URLRequest {
        guard let hop = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return request }
        URLProtocol.removeProperty(forKey: handledKey, in: hop)
        return hop as URLRequest
    }

    private static func readAll(_ stream: InputStream) -> Data {
        let wasOpen = stream.streamStatus != .notOpen
        if !wasOpen {
            stream.open()
        }
        defer {
            if !wasOpen {
                stream.close()
            }
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private func recordTransaction(error: Error?) {
        let httpResponse = receivedResponse as? HTTPURLResponse
        Keep.record(
            KeepHTTPTransaction(
                id: UUID().uuidString,
                label: "URLSession",
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                method: request.httpMethod ?? "GET",
                url: request.url?.absoluteString ?? "",
                requestHeaders: request.allHTTPHeaderFields ?? [:],
                requestBody: requestBody.map(KeepBody.init),
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
