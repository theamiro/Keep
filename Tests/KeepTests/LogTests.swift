import Foundation
import Logging
import Testing
@testable import Keep

@Test
func logMatchesSearchTerms() async throws {
    let metadata: Logger.Metadata = [
        "context": "Authentication",
        "user": "alice",
        "headers": ["Authorization": "Bearer 123", "Content-Type": "application/json"]
    ]
    let log = Log(
        level: .info,
        description: "Login succeeded",
        timestamp: Date(),
        metadata: metadata,
        source: "AuthService",
        file: "AuthService.swift",
        function: "login()",
        line: 42
    )

    #expect(log.matches("alice"))
    #expect(log.matches("authservice"))
    #expect(log.matches("42"))
    #expect(!log.matches("missing"))
}

@Test
func logMetadataSanitizationRedactsSensitiveHeaders() async throws {
    let metadata: Logger.Metadata = [
        "headers": [
            "Authorization": "Bearer 123",
            "access_token": "abc",
            "Content-Type": "application/json"
        ]
    ]
    let log = Log(level: .debug, description: "Redaction", timestamp: Date(), metadata: metadata)

    let data = try JSONEncoder().encode([log])
    let decoded = try JSONDecoder().decode([Log].self, from: data)
    guard let headersValue = decoded.first?.metadata?["headers"],
          case let .dictionary(headersDictionary) = headersValue else {
        Issue.record("Headers metadata should decode to a dictionary")
        return
    }

    if case let .string(authorization) = headersDictionary["Authorization"] {
        #expect(authorization == "[REDACTED]")
    } else {
        Issue.record("Authorization header should be a string")
    }

    if case let .string(accessToken) = headersDictionary["access_token"] {
        #expect(accessToken == "[REDACTED]")
    } else {
        Issue.record("access_token header should be a string")
    }

    if case let .string(contentType) = headersDictionary["Content-Type"] {
        #expect(contentType == "application/json")
    } else {
        Issue.record("Content-Type header should be a string")
    }
}

@Test
func logTagDetectionMatchesContent() async throws {
    let networkLog = Log(level: .info, description: "GET /users", timestamp: Date(), metadata: ["url": "https://example.com"])
    if case .network = networkLog.tag {
        #expect(true)
    } else {
        Issue.record("Expected network tag")
    }

    let memoryLog = Log(level: .debug, description: "Object deinit", timestamp: Date())
    if case .memory = memoryLog.tag {
        #expect(true)
    } else {
        Issue.record("Expected memory tag")
    }

    let unknownLog = Log(level: .error, description: "Unhandled", timestamp: Date())
    if case .unknown = unknownLog.tag {
        #expect(true)
    } else {
        Issue.record("Expected unknown tag")
    }
}
