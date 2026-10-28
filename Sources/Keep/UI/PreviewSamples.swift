#if canImport(UIKit) && DEBUG
    import Foundation
    import Logging

    /// Sample data for Xcode previews. Debug builds only.
    enum PreviewSamples {
        static let info = LogEntry(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1_761_650_000),
            level: .info,
            label: "com.example.checkout",
            message: "Loaded 3 saved cards for the signed-in user",
            metadata: ["cards": .array([.string("visa"), .string("mastercard"), .string("amex")])],
            source: "Checkout",
            file: "CheckoutViewModel.swift",
            function: "loadCards()",
            line: 42,
            tag: "Payments"
        )

        static let error = LogEntry(
            sequence: 2,
            timestamp: Date(timeIntervalSince1970: 1_761_650_003),
            level: .error,
            label: "com.example.checkout",
            message: "Order submission failed after 3 retries. The server returned an unexpected payload and the "
                + "client could not decode the confirmation.",
            metadata: [
                "response": .string(#"{"error":{"code":"ORDER_LOCKED","retryAfter":30,"items":[1,2,3]}}"#),
                "attempt": .string("3")
            ],
            source: "Checkout",
            file: "CheckoutViewModel.swift",
            function: "submitOrder()",
            line: 88,
            tag: "Payments"
        )

        static let pinnedWarning = LogEntry(
            sequence: 3,
            timestamp: Date(timeIntervalSince1970: 1_761_650_010),
            level: .warning,
            label: "com.example.session",
            message: "Token expires in 30 seconds",
            metadata: [:],
            source: "",
            file: "SessionStore.swift",
            function: "refreshIfNeeded()",
            line: 120,
            tag: "Unknown",
            isPinned: true
        )

        static let logs = [pinnedWarning, error, info]

        static let success = KeepHTTPTransaction(
            id: "preview-success",
            label: "api",
            startedAt: Date(timeIntervalSince1970: 1_761_650_001),
            duration: 0.182,
            method: "GET",
            url: "https://api.example.com/v2/cards?include=expired&limit=20",
            requestHeaders: ["Accept": "application/json", "Authorization": "<redacted>"],
            requestBody: nil,
            statusCode: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: KeepBody(
                text: #"{"cards":[{"brand":"visa","last4":"4242"},{"brand":"amex","last4":"0005"}]}"#,
                byteCount: 74,
                isTruncated: false
            ),
            errorDescription: nil
        )

        static let clientError = KeepHTTPTransaction(
            id: "preview-client-error",
            label: "api",
            startedAt: Date(timeIntervalSince1970: 1_761_650_002),
            duration: 0.094,
            method: "POST",
            url: "https://api.example.com/v2/orders",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: KeepBody(text: #"{"cart":"c_123","card":"4242"}"#, byteCount: 30, isTruncated: false),
            statusCode: 409,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: KeepBody(text: #"{"error":"ORDER_LOCKED"}"#, byteCount: 24, isTruncated: false),
            errorDescription: nil
        )

        static let failed = KeepHTTPTransaction(
            id: "preview-failed",
            label: "images",
            startedAt: Date(timeIntervalSince1970: 1_761_650_004),
            duration: 30,
            method: "GET",
            url: "https://cdn.example.com/avatars/42.png",
            requestHeaders: [:],
            requestBody: nil,
            statusCode: nil,
            responseHeaders: [:],
            responseBody: nil,
            errorDescription: "The request timed out."
        )

        static let transactions = [failed, clientError, success]

        /// A running core holding the samples, for previewing the list screens. Writes nothing to disk.
        static func makeCore() -> KeepCore {
            var configuration = KeepConfiguration()
            configuration.crashSnapshotsEnabled = false
            let core = KeepCore(
                configuration: configuration,
                storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("keep-preview"),
                makeKey: { nil }
            )
            for entry in logs.reversed() {
                core.capture(
                    level: entry.level,
                    label: entry.label,
                    message: entry.message,
                    metadata: entry.metadata,
                    source: entry.source,
                    file: entry.file,
                    function: entry.function,
                    line: entry.line
                )
            }
            transactions.reversed().forEach(core.record)
            return core
        }
    }
#endif
