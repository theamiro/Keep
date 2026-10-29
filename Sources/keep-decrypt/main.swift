// Decrypts a file a tester shared from Keep with a password (`KeepSharing.encryptedOnly`).
//
//     swift run keep-decrypt <file.keep> [output directory]
//
// The password is read from the terminal without echo, or from the first line of standard input when it is not a
// terminal. The decrypted file is written under the name it had before it was encrypted, in the output directory
// (the current directory by default). An existing file is never overwritten.

#if os(macOS)
    import Foundation
    import Keep

    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("keep-decrypt: \(message)\n".utf8))
        exit(1)
    }

    func readPassword() -> String {
        if isatty(STDIN_FILENO) != 0 {
            guard let pointer = getpass("Password: ") else { fail("could not read the password") }
            return String(cString: pointer)
        }
        guard let line = readLine(strippingNewline: true) else { fail("no password on standard input") }
        return line
    }

    let arguments = CommandLine.arguments.dropFirst()
    guard (1...2).contains(arguments.count), let inputPath = arguments.first, !inputPath.hasPrefix("-") else {
        fail("usage: keep-decrypt <file.keep> [output directory]")
    }
    let outputDirectory = URL(
        fileURLWithPath: arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath, isDirectory: true)

    let encrypted: Data
    do {
        encrypted = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    } catch {
        fail("could not read \(inputPath): \(error.localizedDescription)")
    }

    let file: KeepFileEncryption.DecryptedFile
    do {
        file = try KeepFileEncryption.decrypt(encrypted, password: readPassword())
    } catch {
        fail(error.localizedDescription)
    }

    // The name comes from the file, so keep only its last component: it must not write outside the output directory.
    let name = (file.fileName as NSString).lastPathComponent
    let safeName = name.isEmpty || name == "." || name == ".." ? "decrypted" : name
    let destination = outputDirectory.appendingPathComponent(safeName)
    guard !FileManager.default.fileExists(atPath: destination.path) else {
        fail("\(destination.path) already exists")
    }
    do {
        try file.contents.write(to: destination, options: .withoutOverwriting)
    } catch {
        fail("could not write \(destination.path): \(error.localizedDescription)")
    }
    print(destination.path)
#else
    print("keep-decrypt runs on macOS.")
#endif
