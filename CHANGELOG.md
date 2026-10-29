# Changelog

## 0.4.0 (unreleased)

### Added

- `KeepConfiguration.accentColor` tints Keep's window, viewer, alerts, share sheet, swipe actions and SwiftUI views. `nil` keeps the system blue, or the host's tint in a viewer embedded with `Keep.makeViewer()`.
- `KeepConfiguration.sharing` decides what testers may send through the share sheet: `.allowed` (the default, as before), `.encryptedOnly` or `.disabled`. Copy actions such as Copy all and Copy cURL are available in every mode. With `.disabled` the Share report items, the lists' share buttons and the details' share actions are removed, and a detail's button becomes a copy menu.
- Password-encrypted shares. With `.encryptedOnly` the tester types a password (at least 8 characters, entered twice) for every share, and Keep shares `<file>.keep`, encrypted with AES-256-GCM and a PBKDF2-SHA256 key. Share text and Share cURL are not offered. Decrypt on a Mac with `swift run keep-decrypt <file.keep>` from the Keep repository, or with `KeepFileEncryption.decrypt(_:password:)`.
- `Keep.exportReport(scope:note:password:)` returns an encrypted report when given a password.

### Changed

- The report zip is removed from the temporary directory when the share sheet closes, as detail files already were.

## 0.3.0 (2026-10-28)

### Changed

- Detail screens have one Share button that opens a menu. Log details offer Copy all, Share text and Share as file. Network details offer Copy cURL, Copy all, Share cURL and Share HAR file. Shared files are removed when the share sheet closes.
- The viewer's tab bar is hidden while a log or network detail is open.

### Fixed

- The back button on a detail screen shows only the chevron, not the title of the list it came from.

## 0.2.0 (2026-10-28)

### Changed

- Redesigned the log and network lists with compact rows, scope filters and count badges, and replaced plain-text detail screens with structured sections and formatted code blocks.
- JSON bodies are pretty-printed and syntax-highlighted with Runestone, including JSON embedded in strings. Code blocks support wrapping, copying formatted or raw text, and showing long content.
- Raised the iOS deployment floor from iOS 13 to iOS 15.
- The viewer's rows, pills, key-value lists and detail sections are now SwiftUI views hosted in the existing UIKit controllers and table views, with Xcode previews. Nothing changes for apps that use Keep.

## 0.1.1 (2026-10-28)

### Fixed

- Shaking the device crashed with `-[UIWindowScene keep_motionEnded:with:]: unrecognized selector` (#9). Keep exchanged `UIWindow.motionEnded` with a renamed selector, and UIKit forwards motion events to the next responder under the name it was called with. Keep now replaces the implementation and calls the previous one under `motionEnded(_:with:)`, so the shake reaches the window scene and the app as before.

## 0.1.0 (2026-10-27)

### Breaking changes

- `Keep.configure(with:)`, `KeepConfiguration(logHandler:…)`, `Keep.logViewController()` and `KeepLogHandler(configuration:)` are replaced by `Keep.start(_:)`, `Keep.makeLogHandler(label:)` and `Keep.present()`. There are no deprecated shims.
- Sessions are kept in memory only. File-backed storage, retention, the session picker and encryption of session files are removed.
- Redaction is always on. `redactsSensitiveInformation` is removed. Use `KeepRedactionPolicy` (`allowedKeys`, `extraKeys`, `extraPatterns`) instead.
- The old `LogTagger.register` API is replaced by `KeepConfiguration.tagRules`.

### Added

- Shake menu on any screen, in Keep's own window: *Share report*, *Log viewer*, *Share crashed session* (when there is one), and tools the app registers with `Keep.registerTool`.
- Distribution gate: `KeepConfiguration.allowedDistributions` plus a runtime kill switch that deletes Keep's folder. App Store builds, and builds whose provisioning profile cannot be read, never run Keep, even when listed.
- Network transactions: `KeepHTTPTransaction`, `Keep.record`, an opt-in `KeepURLProtocol`, cURL output and HAR 1.2 export.
- Shareable report: a zip containing `report.txt`, `logs.jsonl`, `network.har` and `device.json`, with an optional note. The note is redacted like captured text.
- Encrypted crash snapshot (AES-GCM, Keychain key) written on uncaught Objective-C exceptions and offered on the next launch. MetricKit crash reports are recorded on iOS 14+.
- `KeepTagRule` for custom tags.
- `Templates/Diagnostics.swift`, the copy-in file that is the only file importing Keep.
- `Scripts/keep-verify-excluded.sh`, a build check that fails Pilot and Production builds containing Keep. Its tests run with `sh Scripts/keep-verify-excluded.test.sh`.
- `KeepView` and `.keepViewer(isPresented:)` for SwiftUI.
- The UIKit viewer is rebuilt for iOS 13: diffable lists, live updates (coalesced to 250 ms), search, level filter, pinning and a detail view for each log and request.

### Fixed

- Every entry used to rewrite the whole log file on the calling thread. Writes are now queued in memory, off the caller's thread.
- Concurrent handlers could drop entries, and a single corrupt entry could wipe the file. Neither can happen now, because nothing is stored on disk.
- Every log entry with metadata was tagged "HTTP", and any message containing "init" was tagged "Memory". Tags now match explicit signals only.
- The pin toast reported the state from before the change.
- Opening the viewer twice could crash. Each presentation now creates its own viewer.
- The pre-iOS 16 cell sizing and the `document.fill` symbol (unavailable before iOS 17) are gone.

### Changed

- CI builds the UIKit sources for the iOS Simulator and builds the example app's Release configuration, which runs the exclusion check.
- CI now runs on pull requests into `develop` and `master`. It used to target a `main` branch that does not exist, so pull requests were not checked.
- `master` is the release branch. A merge into `master` tags `vX.Y.Z` and publishes a GitHub release from the top `CHANGELOG.md` entry. `Scripts/keep-release-notes.sh` reads that entry and fails when it is undated.
- The ReadME's install snippet pins a released version. It used to pin a `main` branch, which does not exist.
- The example app uses the local package and has a `KEEP_ENABLED` Debug configuration and a Release configuration that excludes Keep.
