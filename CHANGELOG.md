# Changelog

## 0.1.0 (unreleased)

Not yet tagged. Until it is, Swift Package Manager users should pin a branch rather than a version.

### Breaking changes

- `Keep.configure(with:)`, `KeepConfiguration(logHandler:…)`, `Keep.logViewController()` and `KeepLogHandler(configuration:)` are replaced by `Keep.start(_:)`, `Keep.makeLogHandler(label:)` and `Keep.present()`. There are no deprecated shims.
- Sessions are kept in memory only. File-backed storage, retention, the session picker and encryption of session files are removed.
- Redaction is always on. `redactsSensitiveInformation` is removed. Use `KeepRedactionPolicy` (`allowedKeys`, `extraKeys`, `extraPatterns`) instead.
- The old `LogTagger.register` API is replaced by `KeepConfiguration.tagRules`.

### Added

- Shake menu on any screen, in Keep's own window: *Share report*, *Log viewer*, *Share crashed session* (when there is one), and tools the app registers with `Keep.registerTool`.
- Distribution gate: `KeepConfiguration.allowedDistributions` (App Store excluded by default) and a runtime kill switch that deletes Keep's folder in other builds.
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
- The example app uses the local package and has a `KEEP_ENABLED` Debug configuration and a Release configuration that excludes Keep.
