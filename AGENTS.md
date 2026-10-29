# AGENTS.md

Guidance for AI coding agents and people working in this repository.

## What this project is

Keep is in-app diagnostics for internal iOS builds. A tester shakes the device, sees what the app logged and which network requests it made, and shares a report through the system share sheet. It is a Swift package (`Sources/Keep`, tests in `Tests/KeepTests`) plus a sample app (`KeepiOSExample`).

Use the vocabulary in `CONTEXT.md` (Log entry, Network transaction, Session, Redaction, Shake menu, Tool, Log viewer, Report, Note, Internal build, Production build, Tester). If you need a term it does not define, add it to `CONTEXT.md` once it is settled.

## Non-negotiables

These protect the reason Keep exists. Do not change them without an ADR in `docs/adr/` and the user's explicit agreement.

1. **Keep never ships in production.** Only internal app configurations (Development, UAT) get `KEEP_ENABLED`. Pilot and Production exclude Keep and viewer dependency objects; the sample removes Runestone query bundles before running `Scripts/keep-verify-excluded.sh`. The verifier rejects Keep, Runestone and TreeSitter artifacts. Apps import Keep only from one file, `Diagnostics.swift`. Do not add a Keep dependency to a module that every configuration links.
2. **Memory only.** Sessions live in memory. The only disk write is the encrypted crash snapshot (`Storage/CrashSnapshot.swift`). Any new persistence needs an ADR.
3. **Redaction is always on.** Every capture path must go through `Redactor` on Keep's queue, or through `KeepHTTPTransaction.redacted`. Do not add a way to turn it off.
4. **Safety checks fail closed.** The build check and the distribution gate must fail when they cannot decide. An unreadable file is an error, not "no match".

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/Keep/Keep.swift` | Public facade: `start`, `makeLogHandler`, `record`, `registerTool`, `exportReport`, `present` |
| `Sources/Keep/Core/KeepCore.swift` | Capture, redaction, buffers, change notifications, crash snapshot, the process-wide runtime |
| `Sources/Keep/KeepLogHandler.swift` | swift-log backend that forwards to the core |
| `Sources/Keep/Configuration/` | `KeepConfiguration`, `KeepDistribution` and distribution detection |
| `Sources/Keep/Redaction/Redactor.swift` | Key, pattern, header, URL and JSON-body redaction |
| `Sources/Keep/Storage/` | `MemoryBuffer`, encrypted `CrashSnapshot`, Keychain key |
| `Sources/Keep/Model/` | `LogEntry`, `JSONValue`, `KeepTagRule` |
| `Sources/Keep/Network/` | `KeepHTTPTransaction` (cURL output) and the opt-in `KeepURLProtocol` |
| `Sources/Keep/Export/` | `ReportBuilder`, HAR output, `DeviceContext`, `KeepFileEncryption` (password-encrypted shares) |
| `Sources/keep-decrypt/` | macOS command that decrypts `.keep` files. An executable target, not a product |
| `Sources/Keep/Crash/CrashCapture.swift` | Uncaught-exception handler and MetricKit (iOS 14+) |
| `Sources/Keep/UI/` | Viewer controllers (UIKit), shake menu and Keep's window. `KeepHosting.swift` hosts SwiftUI in cells and stacks. Wrapped in `#if canImport(UIKit)` |
| `Sources/Keep/UI/Components/` | SwiftUI views for rows, pills, key-value lists and detail sections, each with a `#Preview`. The Runestone `CodeBlockView` stays UIKit |
| `Sources/Keep/Formatting/` | Platform-neutral display formatting for JSON bodies |
| `Scripts/keep-verify-excluded.sh` | Build check. Its tests are in `Scripts/keep-verify-excluded.test.sh` |
| `Scripts/keep-strip-viewer-resources.sh` | Removes Runestone resources from non-debug sample builds. Its tests are in `Scripts/keep-strip-viewer-resources.test.sh` |
| `Scripts/keep-release-notes.sh` | Reads the release version and notes from `CHANGELOG.md`. Its tests are in `Scripts/keep-release-notes.test.sh` |
| `Templates/Diagnostics.swift` | Copy-in wrapper for apps. `KeepiOSExample/KeepiOSExample/Diagnostics.swift` is a copy and must stay in sync |
| `KeepiOSExample/` | Sample app. Debug has `KEEP_ENABLED`. Release excludes Keep and runs the verify phase |

## Commands

```sh
swift build                 # macOS. UIKit code is excluded here
swift test                  # macOS test suite (Swift Testing)
xcodebuild -scheme Keep -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Keep -destination 'platform=iOS Simulator,name=<installed iPhone>' test
sh Scripts/keep-verify-excluded.test.sh
sh Scripts/keep-strip-viewer-resources.test.sh
sh Scripts/keep-release-notes.test.sh
xcodebuild -project KeepiOSExample/KeepiOSExample.xcodeproj -scheme KeepiOSExample \
  -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
swiftlint lint              # config in .swiftlint.yml. Do not add new warnings
```

Run the macOS tests and the iOS build before opening a PR. Run the iOS test suite too when you touch `Storage`, `Network` or `UI`.

## Conventions

- **Swift 6 language mode** (`swift-tools-version: 6.0`), so strict concurrency applies. UIKit types are `@MainActor`. Shared state is `@unchecked Sendable` behind an `NSLock` (`NSLock.locked` is in `Support/KeepCodec.swift`).
- **Deployment floor is iOS 15 and macOS 12.** Guard newer APIs with `#available`. Use only SF Symbols that exist on iOS 15.
- **Custom UI is SwiftUI, screens are UIKit** (`docs/adr/0002-swiftui-views-in-uikit-controllers.md`). Put new views in `UI/Components` and show them with `KeepHostingCell` or `KeepHostingView`. Add a `#Preview` inside `#if DEBUG`, using `PreviewSamples`. Previews of view controllers need `@available(iOS 17, *)`.
- **Public API is documented** with `///`. Breaking changes go in `CHANGELOG.md` under the next version.
- **Tests** use Swift Testing with the helpers in `Tests/KeepTests/TestSupport.swift` (`makeCore`, `makeLogger`, `makeConfiguration`). Call `core.drainQueue()` before asserting on captured entries. Only `URLProtocolCaptureTests` may install a core into `KeepRuntime.shared`, because the runtime is process-wide.
- **Commits** run the hook in `.githooks`, which runs `swift-format` (from Xcode 16+) and `swiftlint --fix` on staged Swift files. Install `swiftlint` and run `git config core.hooksPath .githooks` first. Re-run the tests after the hook has rewritten files.
- **Docs move with code.** Update `ReadME.md` for user-visible behaviour, `CHANGELOG.md` for changes, and `CONTEXT.md` when a term is settled.
- **Decisions with trade-offs** get an ADR in `docs/adr/` (`NNNN-slug.md`). Use `.claude/skills/grill-with-docs` to work through a design and write the ADR.

## Skills

Project skills live in `.claude/skills/`:

- `grill-with-docs`: interviews the user about a plan until the design is shared, and records terms in `CONTEXT.md` and decisions in `docs/adr/` as they settle. It depends on `grilling` and `domain-modeling`, which are also in `.claude/skills/`.

## Pull requests

- Base branch: `develop`.
- Keep changes focused, and say in the description what you ran to verify them.
- Call out anything that touches the non-negotiables above.
- CI is defined in `.github/workflows/build.yml`. It runs on pushes to `develop` and on PRs into `develop` and `main`.

## Releases

`main` is the release branch, and every merge into it is a release (`docs/adr/0003-release-from-main.md`). The version follows the change (`docs/adr/0004-semver-bump-from-changelog.md`): a top entry with only `### Fixed` or `### Security` headings is a patch, any other allowed heading is a minor, and a major needs the `release:major` label.

1. Feature PRs into `develop` add their notes to the top `CHANGELOG.md` entry, `## X.Y.Z (unreleased)`, under the headings that describe the change (`### Added`, `### Changed`, `### Fixed` and so on). `release-check` fails if `X.Y.Z` is not the version those headings imply after the latest `vX.Y.Z` tag.
2. Open a PR from `develop` into `main` and date that entry, `## X.Y.Z (YYYY-MM-DD)`. The head must be `develop`. `release-check` fails unless the top entry is dated, has notes, and names the expected version.
3. Merge with a merge commit, not a squash, so `main`'s history stays inside `develop`. `.github/workflows/release.yml` then runs the full build, tags `vX.Y.Z` on the merged commit and publishes a GitHub release with that entry's notes.

Do not push to `main` directly, and do not tag releases by hand.
