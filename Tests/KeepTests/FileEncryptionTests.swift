import Foundation
import Testing

@testable import Keep

@Suite("Password-encrypted files")
struct FileEncryptionTests {
    private let password = "correct horse"
    private let contents = Data("{\"log\":{\"entries\":[]}}".utf8)

    @Test func decryptingRestoresTheNameAndContents() throws {
        let sealed = try KeepFileEncryption.encrypt(contents, fileName: "keep-request-1a2b.har", password: password)
        let file = try KeepFileEncryption.decrypt(sealed, password: password)
        #expect(file.fileName == "keep-request-1a2b.har")
        #expect(file.contents == contents)
    }

    @Test func theFileDoesNotContainThePlaintextOrTheName() throws {
        let sealed = try KeepFileEncryption.encrypt(contents, fileName: "secret-name.har", password: password)
        #expect(sealed.range(of: contents) == nil)
        #expect(sealed.range(of: Data("secret-name".utf8)) == nil)
    }

    @Test func eachEncryptionUsesAFreshSaltAndNonce() throws {
        let first = try KeepFileEncryption.encrypt(contents, fileName: "a", password: password)
        let second = try KeepFileEncryption.encrypt(contents, fileName: "a", password: password)
        #expect(first != second)
    }

    @Test func aWrongPasswordFails() throws {
        let sealed = try KeepFileEncryption.encrypt(contents, fileName: "a", password: password)
        #expect(throws: KeepFileEncryptionError.wrongPasswordOrDamaged) {
            try KeepFileEncryption.decrypt(sealed, password: "wrong password")
        }
    }

    @Test(arguments: [8, 9, 40])
    func aModifiedByteFails(offset: Int) throws {
        // 8 is the iteration count's low byte, 9 is in the salt, 40 in the sealed box. All are authenticated.
        var sealed = try KeepFileEncryption.encrypt(contents, fileName: "a", password: password)
        sealed[offset] ^= 0x01
        #expect(throws: KeepFileEncryptionError.wrongPasswordOrDamaged) {
            try KeepFileEncryption.decrypt(sealed, password: password)
        }
    }

    @Test func otherFilesAreRejectedBeforeDerivingAKey() {
        #expect(throws: KeepFileEncryptionError.notAnEncryptedFile) {
            try KeepFileEncryption.decrypt(Data("PK\u{3}\u{4} a zip file, not Keep's".utf8), password: password)
        }
        #expect(throws: KeepFileEncryptionError.notAnEncryptedFile) {
            try KeepFileEncryption.decrypt(Data("KEEP".utf8), password: password)
        }
    }

    @Test func anIterationCountAboveTheCapIsRejectedBeforeDerivingAKey() throws {
        var sealed = try KeepFileEncryption.encrypt(contents, fileName: "a", password: password)
        sealed[5] = 0xFF
        #expect(throws: KeepFileEncryptionError.notAnEncryptedFile) {
            try KeepFileEncryption.decrypt(sealed, password: password)
        }
    }

    @Test func aNewerFormatVersionIsReported() throws {
        var sealed = try KeepFileEncryption.encrypt(contents, fileName: "a", password: password)
        sealed[4] = 2
        #expect(throws: KeepFileEncryptionError.unsupportedVersion) {
            try KeepFileEncryption.decrypt(sealed, password: password)
        }
    }

    @Test func shortPasswordsAreRefused() {
        #expect(throws: KeepFileEncryptionError.passwordTooShort) {
            try KeepFileEncryption.encrypt(contents, fileName: "a", password: "1234567")
        }
    }

    @Test func writingAnEncryptedFileWritesOnlyTheKeepFile() throws {
        let directory = try makeTemporaryDirectory()
        let url = try KeepFileEncryption.writeEncryptedFile(
            contents, fileName: "keep-log-1.txt", password: password, in: directory)
        #expect(url.lastPathComponent == "keep-log-1.txt.keep")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["keep-log-1.txt.keep"])
        #expect(try KeepFileEncryption.decrypt(Data(contentsOf: url), password: password).contents == contents)
    }

    @Test func encryptingAReportReplacesTheZip() throws {
        #if os(macOS)
            let input = ReportInput(
                title: "Current session", logs: [], transactions: [], device: makeDevice(), note: nil,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
            let archive = try ReportBuilder.archive(input)
            let zip = try Data(contentsOf: archive)
            let encrypted = try KeepFileEncryption.encryptFile(at: archive, password: password)

            #expect(!FileManager.default.fileExists(atPath: archive.path))
            #expect(encrypted.lastPathComponent == archive.lastPathComponent + ".keep")
            let file = try KeepFileEncryption.decrypt(Data(contentsOf: encrypted), password: password)
            #expect(file.fileName == archive.lastPathComponent)
            #expect(file.contents == zip)
        #endif
    }
}

@Suite("Sharing modes")
struct SharingTests {
    @Test func sharingIsAllowedByDefault() {
        #expect(KeepConfiguration().sharing == .allowed)
    }

    @Test(arguments: KeepSharing.allCases)
    func eachModeDecidesWhatTheShareSheetMayCarry(mode: KeepSharing) {
        switch mode {
        case .allowed:
            #expect(mode.allowsShareSheet && mode.allowsUnencrypted && !mode.requiresPassword)
        case .encryptedOnly:
            #expect(mode.allowsShareSheet && !mode.allowsUnencrypted && mode.requiresPassword)
        case .disabled:
            #expect(!mode.allowsShareSheet && !mode.allowsUnencrypted && !mode.requiresPassword)
        }
    }
}
