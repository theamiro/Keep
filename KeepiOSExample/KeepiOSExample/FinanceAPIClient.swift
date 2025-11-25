//
//  FinanceAPIClient.swift
//  KeepiOSExample
//
//  Finance-themed mock networking layer that produces sample data
//  and demonstrates Keep logging integration.
//

import Foundation
import Logging

struct Transaction: Codable, Hashable {
    let id: Int
    let merchant: String
    let amount: Double
    let category: String
    let date: Date

    var direction: String { amount >= 0 ? "credit" : "debit" }
}

final class FinanceAPIClient {
    private let logger: Logger
    private let session: URLSession
    private let decoder: JSONDecoder
    private let authToken = "Bearer sk_demo_finance_sample_token_9876543210"

    init(logger: Logger = FinanceLogger.networking) {
        self.logger = logger

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FinanceMockURLProtocol.self]
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5

        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchTransactions(limit: Int = 6, completion: @escaping (Result<[Transaction], Error>) -> Void) {
        guard var components = URLComponents(string: "https://jsonplaceholder.typicode.com/transactions") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        components.queryItems = [URLQueryItem(name: "_limit", value: String(limit))]

        guard let url = components.url else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let requestID = UUID().uuidString
        var request = URLRequest(url: url)
        request.addValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.addValue(authToken, forHTTPHeaderField: "Authorization")

        FinanceLogger.networking.trace("Prepared mocked request", metadata: [
            "limit": .string(String(limit)),
            "method": .string(request.httpMethod ?? "GET"),
            "cache_policy": .string(String(describing: request.cachePolicy)),
            "authorization_token": .string(authToken)
        ])

        logger.info("Authorization bearer token attached:", metadata: [
            "token_suffix": .string(String(authToken.suffix(6)))
        ])

        logger.notice("Starting mocked transaction fetch", metadata: [
            "url": .string(url.absoluteString),
            "request_id": .string(requestID),
            "mocked": .string("true")
        ])

        let start = Date()
        let decoder = self.decoder
        let logger = self.logger

        let task = session.dataTask(with: request) { data, response, error in
            let latency = Date().timeIntervalSince(start) * 1000
            let latencyMS = String(format: "%.0f", latency)

            if let error {
                logger.error("Mocked transaction fetch failed", metadata: [
                    "request_id": .string(requestID),
                    "latency_ms": .string(latencyMS),
                    "error": .string(error.localizedDescription)
                ])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, let data else {
                let failure = URLError(.badServerResponse)
                logger.error("Missing mocked response payload", metadata: [
                    "request_id": .string(requestID),
                    "latency_ms": .string(latencyMS)
                ])
                DispatchQueue.main.async { completion(.failure(failure)) }
                return
            }

            logger.info("Mocked transaction fetch succeeded", metadata: [
                "request_id": .string(requestID),
                "status": .string(String(httpResponse.statusCode)),
                "latency_ms": .string(latencyMS),
                "content_length": .string(String(data.count))
            ])

            let previewData = Data(data.prefix(120))
            if let payloadPreview = String(data: previewData, encoding: .utf8) {
                logger.trace("Mocked payload preview", metadata: [
                    "request_id": .string(requestID),
                    "preview": .string(payloadPreview)
                ])
            }

            do {
                let transactions = try decoder.decode([Transaction].self, from: data)
                if transactions.count < limit {
                    logger.warning("Response returned fewer records than requested", metadata: [
                        "request_id": .string(requestID),
                        "requested": .string(String(limit)),
                        "returned": .string(String(transactions.count))
                    ])
                }
                if let first = transactions.first {
                    logger.debug("First mocked transaction decoded", metadata: [
                        "request_id": .string(requestID),
                        "merchant": .string(first.merchant),
                        "amount": .string(String(format: "%.2f", first.amount))
                    ])
                }
                DispatchQueue.main.async { completion(.success(transactions)) }
            } catch {
                logger.error("Failed to decode mocked response", metadata: [
                    "request_id": .string(requestID),
                    "latency_ms": .string(latencyMS),
                    "error": .string(error.localizedDescription)
                ])
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
}

final class FinanceMockURLProtocol: URLProtocol {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let sampleTransactions: [Transaction] = {
        let now = Date()
        let calendar = Calendar.current

        func daysAgo(_ value: Int) -> Date {
            calendar.date(byAdding: .day, value: -value, to: now) ?? now
        }

        return [
            Transaction(id: 101, merchant: "GreenLeaf Grocers", amount: -54.27, category: "Groceries", date: daysAgo(1)),
            Transaction(id: 102, merchant: "Metro Commute", amount: -3.50, category: "Transport", date: daysAgo(1)),
            Transaction(id: 103, merchant: "Freelance Payment", amount: 650.00, category: "Income", date: daysAgo(2)),
            Transaction(id: 104, merchant: "Fitness App Subscription", amount: -19.99, category: "Health", date: daysAgo(3)),
            Transaction(id: 105, merchant: "Acme Supplies", amount: -122.18, category: "Office", date: daysAgo(4)),
            Transaction(id: 106, merchant: "Evening Bistro", amount: -42.65, category: "Dining", date: daysAgo(5)),
            Transaction(id: 107, merchant: "Dividend Payout", amount: 24.13, category: "Investments", date: daysAgo(6))
        ]
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "jsonplaceholder.typicode.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let limit = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "_limit" })?
            .value
            .flatMap(Int.init) ?? Self.sampleTransactions.count

        let payload = Array(Self.sampleTransactions.prefix(limit))

        FinanceLogger.networking.debug("Serving mocked payload", metadata: [
            "limit": .string(String(limit)),
            "thread": .string(Thread.isMainThread ? "main" : "background")
        ])

        if limit > Self.sampleTransactions.count {
            FinanceLogger.networking.warning("Requested limit exceeds available mock dataset", metadata: [
                "requested": .string(String(limit)),
                "available": .string(String(Self.sampleTransactions.count))
            ])
        }

        do {
            let data = try Self.encoder.encode(payload)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak self] in
                FinanceLogger.networking.trace("Responding with mocked data", metadata: [
                    "queued_delay_ms": .string("800"),
                    "limit": .string(String(limit))
                ])
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
