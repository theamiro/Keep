# 5. Password-encrypted shares and sharing modes

Date: 2026-10-29

## Status

Accepted.

## Context

A report or HAR file shows what an app sends and receives. Redaction removes credentials and personal data it can recognise, but not everything sensitive. Once a tester shares a file, Keep cannot control where it goes. Some teams want to stop the share sheet altogether, and some want shared files to be unreadable without a secret.

The first idea was CryptoSwift. Any third-party code Keep links has to be excluded from production builds and checked by `keep-verify-excluded.sh`, as Runestone and TreeSitter are (non-negotiable 1). CryptoKit and CommonCrypto ship with the OS and already cover what is needed. CryptoKit's AES-GCM is already used for the crash snapshot.

The recipient is usually a developer on a Mac. OpenSSL's `enc` format would open with the `openssl` on every Mac. It only supports CBC, which is unauthenticated, so a wrong password or a modified file could go unnoticed.

## Decision

- `KeepConfiguration.sharing` has three modes. `.allowed` (the default) changes nothing. `.encryptedOnly` shares only encrypted files and hides text shares. `.disabled` removes every share-sheet entry point. Copy actions stay available in every mode. The mode governs the tester's UI only: `Keep.exportReport` is the app's own call.
- Encrypted files use Keep's own format, `<name>.keep`: `"KEEP"`, a version byte, the PBKDF2 iteration count, a 16-byte salt, then an AES-256-GCM box. The key is PBKDF2-HMAC-SHA256 (600,000 iterations) of the password. The header is authenticated. The original file name is sealed with the contents, so it is not visible and is restored on decryption.
- The password is chosen by the tester at share time, typed twice, at least 8 characters. Keep never stores it.
- Decryption is `KeepFileEncryption.decrypt`, a public API that also builds on macOS, and the `keep-decrypt` executable target (`swift run keep-decrypt <file>`). It is not a library product, so apps cannot link it.
- Only the encrypted file is written for detail shares. A report is zipped as before, then the zip is replaced by its encrypted form. Shared files are removed when the share sheet closes.

## Consequences

- No new dependency. The production exclusion and its verifier are unchanged.
- Recipients need a Keep checkout, or their own tool built on `KeepFileEncryption`, to open a file. Standard tools cannot.
- Password strength is up to the tester. PBKDF2 slows guessing but does not stop it for weak passwords. The password must travel separately from the file.
- Copying is still allowed when sharing is disabled. The clipboard can reach other devices through Universal Clipboard. A mode that also blocks copying would be a separate decision.
- No new persistence (non-negotiable 2). Shared files were already written to the temporary directory, and the report zip exists briefly in plaintext before it is encrypted, as it did before.
- The format is versioned. A change of algorithm or iteration count needs a new version byte, and `decrypt` must keep reading version 1.
