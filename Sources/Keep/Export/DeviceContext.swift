import Foundation

enum KeepInfo {
    static let version = "0.1.0"
}

/// Device and app facts included with every report (device.json and the header of report.txt).
struct DeviceContext: Codable, Sendable {
    let appName: String
    let appVersion: String
    let appBuild: String
    let bundleIdentifier: String
    let keepVersion: String
    let distribution: String
    let operatingSystem: String
    let deviceModel: String
    let locale: String
    let timeZone: String
    let freeDiskBytes: Int64?
    let physicalMemoryBytes: UInt64
    let isLowPowerModeEnabled: Bool
    let sessionStartedAt: Date
    let userIdentifier: String?

    static func current(core: KeepCore, sessionStartedAt: Date? = nil) -> DeviceContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let freeDisk = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        return DeviceContext(
            appName: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Unknown",
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            appBuild: info["CFBundleVersion"] as? String ?? "?",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "?",
            keepVersion: KeepInfo.version,
            distribution: core.distribution.rawValue,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: machineIdentifier(),
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            freeDiskBytes: freeDisk,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            sessionStartedAt: sessionStartedAt ?? core.sessionStartedAt,
            userIdentifier: core.currentUserIdentifier
        )
    }

    /// The hardware model identifier, e.g. "iPhone15,2".
    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: systemInfo.machine)) {
                String(cString: $0)
            }
        }
    }
}
