import CryptoKit
import Foundation
@testable import Keep
import Logging

struct StubDetector: KeepDistributionDetecting {
    let value: KeepDistribution
    func detect() -> KeepDistribution {
        value
    }
}

/// A fresh temporary directory for one test.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keep-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeConfiguration(_ distribution: KeepDistribution = .development) -> KeepConfiguration {
    var configuration = KeepConfiguration()
    configuration.distributionDetector = StubDetector(value: distribution)
    return configuration
}

func makeCore(
    _ configuration: KeepConfiguration = makeConfiguration(),
    directory: URL,
    key: SymmetricKey? = SymmetricKey(size: .bits256)
) -> KeepCore {
    KeepCore(configuration: configuration, storageDirectory: directory, makeKey: { key })
}

/// A swift-log `Logger` wired to a core, so tests exercise the same path the app uses.
func makeLogger(_ core: KeepCore, label: String = "tests") -> Logger {
    Logger(label: label, factory: { label in KeepLogHandler(label: label, core: core) })
}

func makeDevice(appName: String = "Eazy", appVersion: String = "1.2", build: String = "45") -> DeviceContext {
    DeviceContext(
        appName: appName,
        appVersion: appVersion,
        appBuild: build,
        bundleIdentifier: "com.example.eazy",
        keepVersion: KeepInfo.version,
        distribution: "development",
        operatingSystem: "Test OS",
        deviceModel: "TestDevice1,1",
        locale: "en_US",
        timeZone: "UTC",
        freeDiskBytes: nil,
        physicalMemoryBytes: 1,
        isLowPowerModeEnabled: false,
        sessionStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
        userIdentifier: nil
    )
}
