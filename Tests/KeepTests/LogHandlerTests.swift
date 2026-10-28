import Foundation
import Logging
import Testing

@testable import Keep

@Suite("swift-log handler")
struct LogHandlerTests {
    @Test func handlerMetadataAndCallSiteMetadataAreMerged() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        var handler = KeepLogHandler(label: "com.example.network", core: core)
        handler[metadataKey: "session"] = .string("abc")
        handler.log(
            level: .info,
            message: "Fetched items",
            metadata: ["status": .string("200")],
            source: "Networking",
            file: "/src/Networking/Client.swift",
            function: "fetch()",
            line: 42
        )
        core.drainQueue()

        let entry = try #require(core.logs.snapshot().first)
        #expect(entry.label == "com.example.network")
        #expect(entry.metadata["session"] == .string("abc"))
        #expect(entry.metadata["status"] == .string("200"))
        #expect(entry.file == "Client.swift")
        #expect(entry.line == 42)
        #expect(entry.source == "Networking")
    }

    @Test func handlerRespectsItsOwnLogLevel() throws {
        let core = try makeCore(directory: makeTemporaryDirectory())
        var handler = KeepLogHandler(label: "t", core: core)
        handler.logLevel = .error
        handler.log(
            level: .debug, message: "quiet", metadata: nil, source: "t", file: "f.swift", function: "f()", line: 1)
        core.drainQueue()
        #expect(core.logs.snapshot().isEmpty)
    }

    @Test func noOpHandlerIsUsedWhenDisabled() throws {
        let core = try makeCore(makeConfiguration(.appStore), directory: makeTemporaryDirectory())
        let logger = Logger(
            label: "disabled",
            factory: { label in
                core.isEnabled ? (KeepLogHandler(label: label, core: core) as LogHandler) : SwiftLogNoOpLogHandler()
            })
        logger.error("never stored")
        core.drainQueue()
        #expect(core.logs.snapshot().isEmpty)
    }
}
