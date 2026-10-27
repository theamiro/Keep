import CryptoKit
import Foundation

/// What Keep keeps across a crash: the session as it was when the uncaught exception was raised.
struct CrashSnapshot: Codable, Sendable {
    let sessionStartedAt: Date
    let logs: [LogEntry]
    let transactions: [KeepHTTPTransaction]
}

/// Writes and reads one AES-GCM encrypted snapshot file. Without a key nothing is written.
struct SnapshotStore: Sendable {
    let directory: URL
    let key: SymmetricKey?

    static let fileName = "crash-snapshot.bin"

    var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    /// Encrypts and atomically writes `snapshot`, replacing any earlier one.
    func write(_ snapshot: CrashSnapshot) {
        guard let key else { return }
        do {
            let plaintext = try KeepCodec.encoder().encode(snapshot)
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try combined.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            Self.excludeFromBackup(directory)
        } catch {
            // A failed snapshot must never take the app down with it; the crash is still in the system crash logs.
        }
    }

    /// Reads and deletes the snapshot. Returns nil if there is none or it cannot be decrypted.
    func loadAndRemove() -> CrashSnapshot? {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let key, let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
            return try KeepCodec.decoder().decode(CrashSnapshot.self, from: plaintext)
        } catch {
            return nil
        }
    }

    static func excludeFromBackup(_ directory: URL) {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
