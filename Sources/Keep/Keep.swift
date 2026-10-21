import Foundation
import Logging

#if canImport(UIKit)
    import UIKit
#endif

/// Keep captures logs and network traffic in internal builds so testers can share what went wrong.
/// See `CONTEXT.md` for the vocabulary used here.
public enum Keep {
    /// Starts Keep. Call once, first thing in `application(_:didFinishLaunchingWithOptions:)`.
    /// Later calls are ignored. Build types outside `allowedDistributions` get a no-op Keep.
    @MainActor
    public static func start(_ configuration: KeepConfiguration = KeepConfiguration()) {
        guard KeepRuntime.shared.current == nil else { return }
        let core = KeepCore(
            configuration: configuration,
            storageDirectory: KeepCore.defaultStorageDirectory(),
            makeKey: { configuration.crashSnapshotsEnabled ? KeychainKey.loadOrCreate() : nil }
        )
        guard KeepRuntime.shared.install(core), core.isEnabled else { return }
        CrashCapture.install(core: core)
        #if canImport(UIKit)
            KeepWindowPresenter.shared.start(shakeEnabled: configuration.shakeToOpen)
        #endif
    }

    /// Whether Keep is running in this build.
    public static var isEnabled: Bool {
        KeepRuntime.shared.current?.isEnabled ?? false
    }

    /// A swift-log backend for `LoggingSystem.bootstrap`. Returns a no-op handler when Keep is not running,
    /// so it is always safe to add to the handler list.
    public static func makeLogHandler(label: String) -> LogHandler {
        guard let core = KeepRuntime.shared.current, core.isEnabled else {
            return SwiftLogNoOpLogHandler()
        }
        return KeepLogHandler(label: label, core: core)
    }

    /// Records an HTTP transaction built from any client. Safe to call from any thread.
    public static func record(_ transaction: KeepHTTPTransaction) {
        guard let core = KeepRuntime.shared.current, core.isEnabled else { return }
        core.record(transaction)
    }

    /// Adds an entry to the shake menu, after "Share report" and "Log viewer".
    /// The action runs on the main thread after the menu closes. Register tools after `start`.
    @MainActor
    public static func registerTool(title: String, action: @escaping @MainActor () -> Void) {
        KeepRuntime.shared.current?.registerTool(title: title, action: action)
    }

    /// Attaches an identifier (for example a user ID) to the device section of future reports. The value is
    /// redacted like other report text, so use an opaque identifier.
    public static func setUserIdentifier(_ identifier: String?) {
        KeepRuntime.shared.current?.setUserIdentifier(identifier)
    }

    /// Builds a report for `scope` and returns the URL of the zip archive. Runs off the main thread.
    public static func exportReport(scope: KeepExportScope = .currentSession, note: String? = nil) async throws -> URL {
        guard let core = KeepRuntime.shared.current, core.isEnabled else {
            throw KeepError.disabled
        }
        let input = try core.reportInput(for: scope, note: note)
        return try ReportBuilder.archive(input)
    }

    #if canImport(UIKit)
        /// Opens the log viewer over the app, from any screen. Does nothing when Keep is not running.
        @MainActor
        public static func present() {
            guard isEnabled else { return }
            KeepWindowPresenter.shared.showViewer()
        }

        /// The log viewer as a view controller, for embedding in your own UI.
        @MainActor
        public static func makeViewer() -> UIViewController {
            KeepViewerViewController()
        }
    #endif
}

/// What a report contains.
public enum KeepExportScope: Sendable {
    /// Everything captured since the app launched.
    case currentSession
    /// The session that ended in a crash before this launch. Available on the launch after the crash only.
    case crashedSession
}

public enum KeepError: LocalizedError, Sendable {
    case disabled
    case noCrashedSession

    public var errorDescription: String? {
        switch self {
        case .disabled: return "Keep is not running in this build."
        case .noCrashedSession: return "There is no crashed session to share."
        }
    }
}
