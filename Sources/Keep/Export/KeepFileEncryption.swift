import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Password encryption for files a tester shares, such as reports and HAR files. See
/// `docs/adr/0005-password-encrypted-shares.md`.
///
/// The key is derived from the password with PBKDF2-HMAC-SHA256 and a random salt, and the file is sealed with
/// AES-256-GCM, so a wrong password or a modified file fails to open instead of producing garbage. The original
/// file name is sealed with the contents. Decrypt a file with `swift run keep-decrypt <file>` from the Keep
/// repository, or with `decrypt(_:password:)`.
public enum KeepFileEncryption {
    /// The extension of an encrypted file: `report.zip` is shared as `report.zip.keep`.
    public static let fileExtension = "keep"
    /// Passwords shorter than this are refused.
    public static let minimumPasswordLength = 8

    /// A decrypted file: the name it had before it was encrypted, and its contents.
    public struct DecryptedFile: Sendable, Equatable {
        /// The name the file had when it was encrypted, such as `keep-request-1a2b.har`. It comes from the file,
        /// so use only its last path component when writing it to disk.
        public let fileName: String
        /// The decrypted contents.
        public let contents: Data
    }

    /// Encrypts `contents` with `password`. Slow on purpose (PBKDF2), so call it off the main thread.
    public static func encrypt(_ contents: Data, fileName: String, password: String) throws -> Data {
        guard password.count >= minimumPasswordLength else {
            throw KeepFileEncryptionError.passwordTooShort
        }
        let salt = try randomBytes(count: saltLength)
        let header = makeHeader(iterations: defaultIterations, salt: salt)
        let key = try deriveKey(password: password, salt: salt, iterations: defaultIterations)
        let name = Data(fileName.utf8.prefix(Int(UInt16.max)))
        var plaintext = Data()
        plaintext.append(contentsOf: [UInt8(name.count >> 8), UInt8(name.count & 0xFF)])
        plaintext.append(name)
        plaintext.append(contents)
        // The header is authenticated too, so the salt and iteration count cannot be swapped.
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = sealed.combined else {
            throw KeepFileEncryptionError.wrongPasswordOrDamaged
        }
        return header + combined
    }

    /// Decrypts a file made by `encrypt(_:fileName:password:)`. Slow on purpose, so call it off the main thread.
    public static func decrypt(_ data: Data, password: String) throws -> DecryptedFile {
        let bytes = [UInt8](data)
        guard bytes.count >= headerLength, Array(bytes[0..<magic.count]) == magic else {
            throw KeepFileEncryptionError.notAnEncryptedFile
        }
        guard bytes[magic.count] == formatVersion else {
            throw KeepFileEncryptionError.unsupportedVersion
        }
        let iterations = bytes[(magic.count + 1)..<(magic.count + 5)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard iterations > 0, iterations <= maximumIterations else {
            throw KeepFileEncryptionError.notAnEncryptedFile
        }
        let header = Data(bytes[0..<headerLength])
        let salt = Data(bytes[(magic.count + 5)..<headerLength])
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            plaintext = try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw KeepFileEncryptionError.wrongPasswordOrDamaged
        }
        let payload = [UInt8](plaintext)
        guard payload.count >= 2 else { throw KeepFileEncryptionError.wrongPasswordOrDamaged }
        let nameLength = Int(payload[0]) << 8 | Int(payload[1])
        guard payload.count >= 2 + nameLength else { throw KeepFileEncryptionError.wrongPasswordOrDamaged }
        guard let fileName = String(bytes: payload[2..<(2 + nameLength)], encoding: .utf8) else {
            throw KeepFileEncryptionError.wrongPasswordOrDamaged
        }
        return DecryptedFile(fileName: fileName, contents: Data(payload[(2 + nameLength)...]))
    }

    // MARK: Format
    // "KEEP" | version (1 byte) | PBKDF2 iterations (UInt32, big-endian) | salt (16 bytes) | AES-GCM combined box.
    // The box is nonce, ciphertext and tag. Its plaintext is name length (UInt16, big-endian) | name | contents.

    private static let magic: [UInt8] = Array("KEEP".utf8)
    private static let formatVersion: UInt8 = 1
    private static let saltLength = 16
    private static let headerLength = magic.count + 1 + 4 + saltLength
    /// OWASP's 2023 recommendation for PBKDF2-HMAC-SHA256.
    static let defaultIterations: UInt32 = 600_000
    /// Bounds the work a crafted file can demand from `decrypt`.
    private static let maximumIterations: UInt32 = 10_000_000

    private static func makeHeader(iterations: UInt32, salt: Data) -> Data {
        var header = Data(magic)
        header.append(formatVersion)
        header.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: iterations >> $0) })
        header.append(salt)
        return header
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw KeepFileEncryptionError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw KeepFileEncryptionError.keyDerivationFailed
        }
        return Data(bytes)
    }
}

/// Why `KeepFileEncryption` could not encrypt or decrypt a file.
public enum KeepFileEncryptionError: LocalizedError, Sendable, Equatable {
    /// The password is shorter than `KeepFileEncryption.minimumPasswordLength`.
    case passwordTooShort
    /// The data does not start with Keep's header, or its header is invalid.
    case notAnEncryptedFile
    /// The file uses a format version this Keep cannot read.
    case unsupportedVersion
    /// The password is wrong, or the file was modified or truncated. The two cannot be told apart.
    case wrongPasswordOrDamaged
    /// The system could not derive a key or generate random bytes.
    case keyDerivationFailed

    /// A sentence to show the tester or print from a command-line tool.
    public var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "The password must be at least \(KeepFileEncryption.minimumPasswordLength) characters."
        case .notAnEncryptedFile: return "This is not a file encrypted by Keep."
        case .unsupportedVersion: return "This file was encrypted by a newer version of Keep."
        case .wrongPasswordOrDamaged: return "The password is wrong, or the file is damaged."
        case .keyDerivationFailed: return "Could not derive a key from the password."
        }
    }
}

extension KeepFileEncryption {
    /// Encrypts `contents` and writes it to `directory` as `<fileName>.keep`. The plaintext is never written.
    static func writeEncryptedFile(
        _ contents: Data,
        fileName: String,
        password: String,
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let sealed = try encrypt(contents, fileName: fileName, password: password)
        let url = directory.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
        try sealed.write(to: url, options: .atomic)
        return url
    }

    /// Replaces the file at `url` with its encrypted form, `<name>.keep` in the same directory.
    static func encryptFile(at url: URL, password: String) throws -> URL {
        defer { try? FileManager.default.removeItem(at: url) }
        return try writeEncryptedFile(
            Data(contentsOf: url),
            fileName: url.lastPathComponent,
            password: password,
            in: url.deletingLastPathComponent()
        )
    }
}
