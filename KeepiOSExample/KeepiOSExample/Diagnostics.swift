//
//  Diagnostics.swift
//
//  Copy this file into your app target. It is the only file that imports Keep.
//  Keep is compiled in only when the KEEP_ENABLED condition is set (add it to Development and UAT
//  configurations, never to Pilot or Production). Without the condition every member is a no-op.
//

import Foundation
import Logging

#if KEEP_ENABLED
    import Keep
#endif

enum Diagnostics {
    /// Starts Keep. Call first in `application(_:didFinishLaunchingWithOptions:)`, before anything logs.
    @MainActor
    static func start() {
        #if KEEP_ENABLED
            var configuration = KeepConfiguration()
            configuration.minimumLevel = .trace
            Keep.start(configuration)
        #endif
    }

    /// Handlers to add to your `MultiplexLogHandler` in `LoggingSystem.bootstrap`. Empty when Keep is not compiled in.
    nonisolated static func logHandlers(label: String) -> [LogHandler] {
        #if KEEP_ENABLED
            return [Keep.makeLogHandler(label: label)]
        #else
            return []
        #endif
    }

    /// Whether Keep is running in this build.
    nonisolated static var isEnabled: Bool {
        #if KEEP_ENABLED
            return Keep.isEnabled
        #else
            return false
        #endif
    }

    /// Opens the log viewer from any screen. Wire this to a debug button if you want one.
    @MainActor
    static func present() {
        #if KEEP_ENABLED
            Keep.present()
        #endif
    }
}

#if KEEP_ENABLED && canImport(Alamofire)
    // Alamofire capture. Not compiled in the Keep repository (Alamofire is not a dependency there).
    // Verify against your Alamofire version before relying on it.
    import Alamofire

    final class KeepEventMonitor: EventMonitor {
        let queue = DispatchQueue(label: "com.keep.event-monitor")
        private var startDates: [UUID: Date] = [:]

        func requestDidResume(_ request: Request) {
            queue.async { self.startDates[request.id] = Date() }
        }

        func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
            queue.async {
                let startedAt = self.startDates.removeValue(forKey: request.id) ?? Date()
                guard let urlRequest = request.request else { return }
                Keep.record(KeepHTTPTransaction(
                    label: "Alamofire",
                    startedAt: startedAt,
                    duration: Date().timeIntervalSince(startedAt),
                    request: urlRequest,
                    response: response.response,
                    requestBody: urlRequest.httpBody,
                    responseBody: response.data,
                    error: response.error
                ))
            }
        }
    }
#endif
