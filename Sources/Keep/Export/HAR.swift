import Foundation

/// HAR 1.2 output, so a transaction or session opens in browser dev tools and proxy viewers.
enum HAR {
    static func data(for transactions: [KeepHTTPTransaction], creatorVersion: String) throws -> Data {
        let entries = transactions.sorted { $0.startedAt < $1.startedAt }.map(entry)
        let root = Root(log: Root.Log(
            version: "1.2",
            creator: Root.Creator(name: "Keep", version: creatorVersion),
            entries: entries
        ))
        return try KeepCodec.encoder(pretty: true).encode(root)
    }

    private static func entry(_ transaction: KeepHTTPTransaction) -> Entry {
        let durationMS = transaction.duration * 1000
        let requestHeaders = transaction.requestHeaders.map { Header(name: $0.key, value: $0.value) }
        let responseHeaders = transaction.responseHeaders.map { Header(name: $0.key, value: $0.value) }
        let mimeType = transaction.responseHeaders.first { $0.key.lowercased() == "content-type" }?.value ?? ""
        return Entry(
            startedDateTime: transaction.startedAt,
            time: durationMS,
            request: Entry.Request(
                method: transaction.method,
                url: transaction.url,
                httpVersion: "HTTP/1.1",
                headers: requestHeaders,
                queryString: [],
                headersSize: -1,
                bodySize: transaction.requestBody?.byteCount ?? 0,
                postData: transaction.requestBody.map {
                    Entry.Request.PostData(
                        mimeType: transaction.requestHeaders.first { $0.key.lowercased() == "content-type" }?.value ?? "",
                        text: $0.text
                    )
                }
            ),
            response: Entry.Response(
                status: transaction.statusCode ?? 0,
                statusText: transaction.errorDescription ?? "",
                httpVersion: "HTTP/1.1",
                headers: responseHeaders,
                content: Entry.Response.Content(
                    size: transaction.responseBody?.byteCount ?? 0,
                    mimeType: mimeType,
                    text: transaction.responseBody?.text ?? ""
                ),
                redirectURL: "",
                headersSize: -1,
                bodySize: transaction.responseBody?.byteCount ?? 0
            ),
            timings: Entry.Timings(send: 0, wait: durationMS, receive: 0)
        )
    }

    private struct Root: Encodable {
        let log: Log

        struct Log: Encodable {
            let version: String
            let creator: Creator
            let entries: [Entry]
        }

        struct Creator: Encodable {
            let name: String
            let version: String
        }
    }

    private struct Header: Encodable {
        let name: String
        let value: String
    }

    private struct Entry: Encodable {
        let startedDateTime: Date
        let time: Double
        let request: Request
        let response: Response
        let cache: [String: String] = [:]
        let timings: Timings

        struct Request: Encodable {
            let method: String
            let url: String
            let httpVersion: String
            let headers: [Header]
            let queryString: [Header]
            let headersSize: Int
            let bodySize: Int
            let postData: PostData?

            struct PostData: Encodable {
                let mimeType: String
                let text: String
            }
        }

        struct Response: Encodable {
            let status: Int
            let statusText: String
            let httpVersion: String
            let headers: [Header]
            let content: Content
            let redirectURL: String
            let headersSize: Int
            let bodySize: Int

            struct Content: Encodable {
                let size: Int
                let mimeType: String
                let text: String
            }
        }

        struct Timings: Encodable {
            let send: Double
            let wait: Double
            let receive: Double
        }
    }
}
