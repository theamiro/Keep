import Foundation
import Logging

/// Settings for `Keep.start`. Keep is a no-op unless the running build's distribution is in `allowedDistributions`.
public struct KeepConfiguration: Sendable {
    /// Entries below this level are never captured.
    public var minimumLevel: Logger.Level = .trace
    /// Maximum log entries kept in memory. Pinned entries are evicted last.
    public var memoryCapacity: Int = 2000
    /// Maximum network transactions kept in memory.
    public var networkCapacity: Int = 200
    /// Keys whose values are never redacted, and extra sensitive keys or patterns.
    public var redaction = KeepRedactionPolicy()
    /// Build types that may run Keep. Production (App Store) is never included.
    public var allowedDistributions: Set<KeepDistribution> = [.simulator, .development, .adHoc, .testFlight]
    /// Opens the shake menu on device shake.
    public var shakeToOpen: Bool = true
    /// Tag rules, checked in order.
    public var tagRules: [KeepTagRule] = KeepTagRule.defaults
    /// Writes the session to an encrypted file on an uncaught exception so the next launch can offer it.
    public var crashSnapshotsEnabled: Bool = true

    public init() {}

    var distributionDetector: any KeepDistributionDetecting = LiveDistributionDetector()
}

/// How the running app was distributed. Derived at launch; see `LiveDistributionDetector`.
public enum KeepDistribution: String, Sendable, CaseIterable {
    case simulator
    case development
    case adHoc
    case testFlight
    case appStore
}

protocol KeepDistributionDetecting: Sendable {
    func detect() -> KeepDistribution
}

/// Reads the build's provisioning state. App Store builds have no embedded profile and no sandbox receipt.
struct LiveDistributionDetector: KeepDistributionDetecting {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func detect() -> KeepDistribution {
        #if targetEnvironment(simulator)
            return .simulator
        #else
            if let profileURL = bundle.url(forResource: "embedded", withExtension: "mobileprovision") {
                return Self.isDevelopmentProfile(at: profileURL) ? .development : .adHoc
            }
            if bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
                return .testFlight
            }
            return .appStore
        #endif
    }

    /// The profile is a CMS envelope whose plist payload is plain XML, so the key can be searched for directly.
    static func isDevelopmentProfile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let key = Data("<key>get-task-allow</key>".utf8)
        guard let keyRange = data.range(of: key) else { return false }
        let window = data[keyRange.upperBound ..< min(data.endIndex, keyRange.upperBound + 64)]
        return window.range(of: Data("<true/>".utf8)) != nil
    }
}
