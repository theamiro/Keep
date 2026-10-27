import Foundation

/// Records uncaught Objective-C exceptions synchronously, and crash reports that MetricKit delivers on later launches.
/// Signal-level crashes (e.g. EXC_BAD_ACCESS) are not caught here; MetricKit reports them on the next launch.
enum CrashCapture {
    private nonisolated(unsafe) static var core: KeepCore?
    private nonisolated(unsafe) static var previousHandler: (@convention(c) (NSException) -> Void)?
    private nonisolated(unsafe) static var metricSubscriber: AnyObject?

    static func install(core: KeepCore) {
        guard core.configuration.crashSnapshotsEnabled else { return }
        self.core = core
        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashCapture.handle(exception)
        }
        #if os(iOS)
            if #available(iOS 14.0, *) {
                let subscriber = KeepMetricSubscriber(core: core)
                MetricKitBridge.subscribe(subscriber)
                metricSubscriber = subscriber
            }
        #endif
    }

    private static func handle(_ exception: NSException) {
        core?.recordCrash(
            name: exception.name.rawValue,
            reason: exception.reason ?? "",
            callStack: exception.callStackSymbols
        )
        previousHandler?(exception)
    }
}

#if os(iOS)
    import MetricKit

    /// Kept separate so the MetricKit types only load where they exist.
    enum MetricKitBridge {
        static func subscribe(_ subscriber: AnyObject) {
            guard let subscriber = subscriber as? MXMetricManagerSubscriber else { return }
            MXMetricManager.shared.add(subscriber)
        }
    }

    @available(iOS 14.0, *)
    final class KeepMetricSubscriber: NSObject, MXMetricManagerSubscriber {
        private let core: KeepCore

        init(core: KeepCore) {
            self.core = core
        }

        func didReceive(_: [MXMetricPayload]) {}

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads {
                for crash in payload.crashDiagnostics ?? [] {
                    core.recordDiagnostic(
                        message: "Crash report from previous session",
                        details: String(decoding: crash.jsonRepresentation(), as: UTF8.self)
                    )
                }
            }
        }
    }
#endif
