import Foundation
import Logging

#if canImport(UIKit)
    import UIKit
#endif

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
    /// Build types that may run Keep. App Store builds, and builds whose distribution cannot be determined,
    /// never run Keep, even when listed here.
    public var allowedDistributions: Set<KeepDistribution> = [.simulator, .development, .adHoc, .testFlight]
    /// Opens the shake menu on device shake.
    public var shakeToOpen: Bool = true
    /// Tag rules, checked in order.
    public var tagRules: [KeepTagRule] = KeepTagRule.defaults
    /// Writes the session to an encrypted file on an uncaught exception so the next launch can offer it.
    public var crashSnapshotsEnabled: Bool = true
    /// What testers may send through the system share sheet. Copy actions are always available.
    public var sharing: KeepSharing = .allowed

    #if canImport(UIKit)
        /// Tint for Keep's buttons, controls and highlights. `nil` uses the system blue in Keep's own window, and
        /// the host's tint in a viewer embedded with `Keep.makeViewer()`.
        public var accentColor: UIColor?
    #endif

    public init() {}

    var distributionDetector: any KeepDistributionDetecting = LiveDistributionDetector()
}

/// What testers may send through the system share sheet from the shake menu and the log viewer. Copy actions,
/// such as Copy all and Copy cURL, are available in every mode. `Keep.exportReport` is not affected, because the
/// app calls it, not the tester.
public enum KeepSharing: Sendable, CaseIterable {
    /// Reports, files and text can be shared unencrypted, as before.
    case allowed
    /// Only files encrypted with a password the tester chooses when sharing. Sharing plain text is not offered.
    /// See `KeepFileEncryption`.
    case encryptedOnly
    /// Nothing can be shared. The Share report items, the lists' share buttons and the details' share actions are
    /// removed.
    case disabled
}

extension KeepSharing {
    /// Whether the share sheet may be offered at all.
    var allowsShareSheet: Bool {
        self != .disabled
    }

    /// Whether text and files may be shared without a password.
    var allowsUnencrypted: Bool {
        self == .allowed
    }

    /// Whether every share must be an encrypted file.
    var requiresPassword: Bool {
        self == .encryptedOnly
    }
}

/// How the running app was distributed. Derived at launch; see `LiveDistributionDetector`.
public enum KeepDistribution: String, Sendable, CaseIterable {
    case simulator
    case development
    case adHoc
    case testFlight
    case appStore
    /// The provisioning profile could not be read or classified. Never runs Keep.
    case unknown
}

extension KeepDistribution {
    /// App Store builds and builds of unknown distribution never run Keep, whatever the configuration says.
    var mayRunKeep: Bool {
        self != .appStore && self != .unknown
    }
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
                return Self.profileDistribution(at: profileURL)
            }
            if bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
                return .testFlight
            }
            return .appStore
        #endif
    }

    /// The profile is a CMS envelope whose plist payload is plain XML. Reads the `get-task-allow` value that
    /// follows the key. Returns `.unknown` when the file cannot be read or the value is missing or unrecognised.
    static func profileDistribution(at url: URL) -> KeepDistribution {
        guard let data = try? Data(contentsOf: url) else { return .unknown }
        let key = Data("<key>get-task-allow</key>".utf8)
        guard let keyRange = data.range(of: key) else { return .unknown }
        let value = data[keyRange.upperBound...].prefix(64).drop(while: { [0x20, 0x09, 0x0A, 0x0D].contains($0) })
        if value.starts(with: Data("<true/>".utf8)) {
            return .development
        }
        if value.starts(with: Data("<false/>".utf8)) {
            return .adHoc
        }
        return .unknown
    }
}
