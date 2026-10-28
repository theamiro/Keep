import Combine
import CryptoKit
import Foundation
import Logging

/// Owns one Keep session: the bounded buffers, redaction, the change notifications and the crash snapshot.
/// `Keep.start` creates the single shared instance; tests create their own.
final class KeepCore: @unchecked Sendable {
    let configuration: KeepConfiguration
    let distribution: KeepDistribution
    let isEnabled: Bool
    let sessionStartedAt: Date
    /// The session that was running when the app last crashed, loaded and removed at start. Nil if none.
    let previousSnapshot: CrashSnapshot?

    let logs: MemoryBuffer<LogEntry>
    let transactions: MemoryBuffer<KeepHTTPTransaction>
    /// Fires on the main thread after logs or transactions change. Coalesced, so bursts produce one event.
    let changes = PassthroughSubject<Void, Never>()

    private let redactor: Redactor
    private let queue = DispatchQueue(label: "com.keep.core", qos: .utility)
    private let stateLock = NSLock()
    private let snapshotStore: SnapshotStore?
    private var lastSequence = 0
    private var notificationPending = false
    private var userIdentifier: String?
    private var tools: [(title: String, action: @MainActor () -> Void)] = []

    init(
        configuration: KeepConfiguration,
        storageDirectory: URL,
        makeKey: () -> SymmetricKey?,
        startedAt: Date = Date()
    ) {
        let detected = configuration.distributionDetector.detect()
        self.configuration = configuration
        sessionStartedAt = startedAt
        distribution = detected
        isEnabled = detected.mayRunKeep && configuration.allowedDistributions.contains(detected)
        redactor = Redactor(policy: configuration.redaction)
        logs = MemoryBuffer(
            capacity: configuration.memoryCapacity,
            isProtected: { $0.isPinned },
            order: { $0.sequence > $1.sequence }
        )
        transactions = MemoryBuffer(
            capacity: configuration.networkCapacity,
            order: { $0.startedAt > $1.startedAt }
        )

        if isEnabled {
            let store =
                configuration.crashSnapshotsEnabled
                ? SnapshotStore(directory: storageDirectory, key: makeKey())
                : nil
            snapshotStore = store
            previousSnapshot = store?.loadAndRemove()
        } else {
            // Kill switch: a build that is not allowed to run Keep must not leave anything behind.
            snapshotStore = nil
            previousSnapshot = nil
            try? FileManager.default.removeItem(at: storageDirectory)
        }
    }

    static func defaultStorageDirectory() -> URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Keep", isDirectory: true)
    }

    // MARK: Capture

    /// Called on the logging thread. Only the sequence number is assigned here; redaction runs on the core queue.
    func capture(
        level: Logger.Level,
        label: String,
        message: String,
        metadata: [String: JSONValue],
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard isEnabled else { return }
        let sequence = nextSequence()
        let timestamp = Date()
        queue.async { [self] in
            let entry = makeEntry(
                sequence: sequence, timestamp: timestamp, level: level, label: label, message: message,
                metadata: metadata, source: source, file: file, function: function, line: line
            )
            logs.append(entry)
            scheduleNotification()
        }
    }

    func record(_ transaction: KeepHTTPTransaction) {
        guard isEnabled else { return }
        queue.async { [self] in
            transactions.append(transaction.redacted(redactor))
            scheduleNotification()
        }
    }

    /// Synchronous capture for the uncaught-exception handler. Writes the snapshot before returning.
    func recordCrash(name: String, reason: String, callStack: [String]) {
        guard isEnabled else { return }
        // Let captures that are already queued land first. The wait is bounded, so an exception raised on the
        // queue itself cannot deadlock the handler.
        let drained = DispatchSemaphore(value: 0)
        queue.async { drained.signal() }
        _ = drained.wait(timeout: .now() + 0.5)
        let entry = makeEntry(
            sequence: nextSequence(), timestamp: Date(), level: .critical, label: "Keep",
            message: "Uncaught exception \(name): \(reason)",
            metadata: ["callStack": .array(callStack.prefix(64).map { .string($0) })],
            source: "Keep", file: #fileID, function: #function, line: #line
        )
        logs.append(entry)
        snapshotStore?.write(
            CrashSnapshot(
                sessionStartedAt: sessionStartedAt,
                logs: logs.snapshot(),
                transactions: transactions.snapshot()
            ))
    }

    /// Records a crash report delivered later by MetricKit into the current session.
    func recordDiagnostic(message: String, details: String) {
        capture(
            level: .critical, label: "Keep", message: message,
            metadata: ["diagnostic": .string(String(details.prefix(64 * 1024)))],
            source: "MetricKit", file: #fileID, function: #function, line: #line
        )
    }

    // MARK: Reports

    /// The contents of a report for `scope`. The note is redacted with the same rules as captured text.
    func reportInput(for scope: KeepExportScope, note: String?, generatedAt: Date = Date()) throws -> ReportInput {
        let redactedNote = note.map { redactor.redact(message: $0) }
        switch scope {
        case .currentSession:
            return ReportInput(
                title: "Current session",
                logs: logs.snapshot(),
                transactions: transactions.snapshot(),
                device: DeviceContext.current(core: self),
                note: redactedNote,
                generatedAt: generatedAt
            )
        case .crashedSession:
            guard let snapshot = previousSnapshot else {
                throw KeepError.noCrashedSession
            }
            return ReportInput(
                title: "Crashed session",
                logs: snapshot.logs,
                transactions: snapshot.transactions,
                device: DeviceContext.current(core: self, sessionStartedAt: snapshot.sessionStartedAt),
                note: redactedNote,
                generatedAt: generatedAt
            )
        }
    }

    // MARK: Viewer actions

    /// Toggles the pin and returns the new state, or nil if the entry is gone.
    func togglePin(id: String) -> Bool? {
        var pinned: Bool?
        let found = logs.modify(where: { $0.id == id }) { entry in
            entry.isPinned.toggle()
            pinned = entry.isPinned
        }
        return found ? pinned : nil
    }

    /// Waits until captures queued so far are stored. Exists for tests.
    func drainQueue() {
        queue.sync {}
    }

    func clearSession() {
        logs.removeAll()
        transactions.removeAll()
        scheduleNotification()
    }

    // MARK: Tools and identity

    func registerTool(title: String, action: @escaping @MainActor () -> Void) {
        stateLock.locked { tools.append((title, action)) }
    }

    var registeredTools: [(title: String, action: @MainActor () -> Void)] {
        stateLock.locked { tools }
    }

    func setUserIdentifier(_ identifier: String?) {
        stateLock.locked { userIdentifier = identifier }
    }

    /// The identifier the app set, redacted like other report text.
    var reportUserIdentifier: String? {
        stateLock.locked { userIdentifier }.map { redactor.redact(message: $0) }
    }

    // MARK: Private

    private func nextSequence() -> Int {
        stateLock.locked {
            lastSequence += 1
            return lastSequence
        }
    }

    private func makeEntry(
        sequence: Int,
        timestamp: Date,
        level: Logger.Level,
        label: String,
        message: String,
        metadata: [String: JSONValue],
        source: String,
        file: String,
        function: String,
        line: UInt
    ) -> LogEntry {
        let redactedMessage = redactor.redact(message: message)
        let redactedMetadata = redactor.redact(metadata: metadata)
        let tag = KeepTagRule.title(
            for: redactedMessage,
            metadataKeys: Set(redactedMetadata.keys),
            rules: configuration.tagRules
        )
        return LogEntry(
            sequence: sequence,
            timestamp: timestamp,
            level: level,
            label: label,
            message: redactedMessage,
            metadata: redactedMetadata,
            source: source,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line,
            tag: tag
        )
    }

    private func scheduleNotification() {
        let shouldSchedule = stateLock.locked { () -> Bool in
            guard !notificationPending else { return false }
            notificationPending = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [self] in
            stateLock.locked { notificationPending = false }
            changes.send()
        }
    }
}

/// Holds the one `KeepCore` created by `Keep.start`.
final class KeepRuntime: @unchecked Sendable {
    static let shared = KeepRuntime()

    private let lock = NSLock()
    private var core: KeepCore?

    var current: KeepCore? {
        lock.locked { core }
    }

    /// Stores `candidate` unless a core is already installed. Returns whether it was stored.
    func install(_ candidate: KeepCore) -> Bool {
        lock.locked {
            guard core == nil else { return false }
            core = candidate
            return true
        }
    }
}
