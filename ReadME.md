# Keep – In-App Diagnostics for Internal iOS Builds

<p align="left">
<img src="https://github.com/theamiro/Keep/actions/workflows/build.yml/badge.svg" />
<img src="https://img.shields.io/badge/platform-iOS-brightgreen" />
<a href="https://github.com/kefranabg/readme-md-generator/blob/master/LICENSE">
    <img alt="License: MIT"  src="https://img.shields.io/badge/license-MIT-yellow.svg"  target="_blank" />
</a>
</p>

**Keep** is a Chucker-style diagnostics tool for iOS. Testers open it with a shake, see what the app logged and which network requests it made, and share a report through the system share sheet. It captures [swift-log](https://github.com/apple/swift-log) messages and HTTP transactions in memory, redacts sensitive values before they are stored, and is compiled out of production builds.

Keep supports iOS 15 and later.

## Why Keep?

- **Opens from anywhere.** A shake opens the menu on any screen, including the splash screen, the login screen and over a certificate-failure alert. It runs in its own window, so it does not depend on your navigation.
- **Memory only.** Sessions live in memory. The only thing written to disk is an encrypted crash snapshot, which is removed on the next launch.
- **Redacted by default.** Bearer tokens, JWTs, passwords, emails, phone numbers, SSNs and Luhn-valid card numbers are removed before they are stored. Redaction cannot be turned off.
- **Never in production.** Keep is linked only into internal builds. A build check fails if Keep's code ever reaches a production binary. A runtime check turns Keep off in App Store builds as a backstop.

## Getting Started

### Installation (Swift Package Manager)

Add Keep to your package manifest and pin a released version. Releases are tagged from the `main` branch and listed in [`CHANGELOG.md`](CHANGELOG.md):

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/theamiro/Keep.git",
        from: "0.1.1"
    )
]
```

Then include `Keep` in the target that requires logging support:

```swift
.target(
    name: "AppModule",
    dependencies: ["Keep"]
)
```

In Xcode you can also choose **File ▸ Add Packages…** and paste the repository URL.

### Start Keep

Create a `Diagnostics.swift` in your app target from [`Templates/Diagnostics.swift`](Templates/Diagnostics.swift). It is the only file that imports Keep. Then start Keep first thing in `application(_:didFinishLaunchingWithOptions:)`, and add its log handler to your swift-log bootstrap:

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Diagnostics.start()

    LoggingSystem.bootstrap { label in
        var consoleHandler = StreamLogHandler.standardOutput(label: label)
        consoleHandler.logLevel = .info
        return MultiplexLogHandler([consoleHandler] + Diagnostics.logHandlers(label: label))
    }
    return true
}
```

Inside `Diagnostics.start()`, Keep is configured with `KeepConfiguration`. The defaults are the ones you usually want:

```swift
var configuration = KeepConfiguration()
configuration.minimumLevel = .debug            // drop anything below debug
configuration.memoryCapacity = 2_000           // log entries kept in memory
configuration.shakeToOpen = true               // shake opens the menu
configuration.redaction.allowedKeys = ["page"] // keys that must never be redacted
configuration.redaction.extraKeys = ["customerRef"]
Keep.start(configuration)
```

`Keep.start` is idempotent, so calling it again is harmless.

### Keep it out of production

Keep is protected at five layers. The first three keep it out of production builds. The other two catch mistakes:

1. **Compile gate.** Add `KEEP_ENABLED` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for Development and UAT configurations only. `Diagnostics.swift` compiles to no-ops without it.
2. **Link exclusion.** For Pilot and Production configurations, exclude `Keep.o` and the Runestone/TreeSitter product objects with `EXCLUDED_SOURCE_FILE_NAMES`. The sample project lists the current object names in its Release configuration.
3. **Resource cleanup.** Run [`Scripts/keep-strip-viewer-resources.sh`](Scripts/keep-strip-viewer-resources.sh) before the verifier for non-debug configurations to remove the Runestone query bundles.
4. **Build check.** Add [`Scripts/keep-verify-excluded.sh`](Scripts/keep-verify-excluded.sh) as a Run Script build phase after linking and resource cleanup. Set `KEEP_FORBIDDEN_CONFIGURATIONS` to a semicolon-separated list of configuration names (default `Release`). The build fails if Keep, Runestone or TreeSitter code or resources are found, and it fails if the executable cannot be read.
5. **Runtime kill switch.** `Keep.start` detects how the app was distributed. App Store builds, and builds whose provisioning profile cannot be read, turn Keep off and delete its folder, whatever `allowedDistributions` says.

The example app's Release configuration uses layers 2–4. Its Debug configuration has `KEEP_ENABLED`. See `KeepiOSExample/KeepiOSExample.xcodeproj`.

> **Limit of layer 5.** An Ad Hoc build of a production configuration looks the same as an internal Ad Hoc build at runtime, so the runtime check cannot tell them apart. Layers 1–4 are the build-time guard for those builds.

### Open the log viewer

- **Shake** the device on any screen. The shake menu offers *Share report*, *Log viewer*, *Share crashed session* (when there is one) and any tools you registered.
- **Programmatically**, from a debug menu: `Diagnostics.present()`, which calls `Keep.present()`.
- **SwiftUI**: `.keepViewer(isPresented:)` shows the viewer as a sheet, using `KeepView`.

The viewer groups pinned logs first and shows compact time, level, source and message rows. Search the logs and filter with **All**, **Info+**, **Warn+** or **Error**. Network rows show the method, status, path, duration and response size; their scope filters are **All**, **2xx**, **4xx**, **5xx** and **Failed**.

Log and network details use separate sections for fields, headers and bodies. JSON bodies are pretty-printed and syntax-highlighted, including JSON embedded in a response string. Each code block has a **Wrap** toggle, **Copy** button and long-press options for copying formatted or raw text. **Copy all** copies the complete plain-text detail.

Register your own tools so they appear in the shake menu:

```swift
Keep.registerTool(title: "Design system") {
    DesignSystemPreviewCoordinator.present()
}
```

Tools run after the menu closes and Keep's window is hidden, so they present over your app.

### Capture network traffic

Keep stores HTTP transactions from any client. Build a `KeepHTTPTransaction` from a `URLRequest` and its response, and record it:

```swift
Keep.record(KeepHTTPTransaction(
    label: "Alamofire",
    startedAt: startedAt,
    duration: duration,
    request: urlRequest,
    response: response,
    responseBody: data,
    error: error
))
```

For URLSession, `KeepURLProtocol.install(on:)` captures traffic from a configuration you choose. It forwards each request through its own session, so the app sees the same responses and redirects. Limits: it uses default session settings, background sessions are not captured, and the app's session delegate (for example certificate pinning) does not see the request. Do not use it on sessions that rely on that delegate.

For Alamofire, use an `EventMonitor` that calls `Keep.record`. The copy-in template includes one, guarded by `#if canImport(Alamofire)`.

### Share a report

Shake, then choose *Share report*, or use the Share button in the viewer. Keep asks for an optional note and builds a zip with:

- `report.txt`: device and app context, the note, and a readable log
- `logs.jsonl`: one log entry per line
- `network.har`: HAR 1.2, which opens in browser dev tools and proxy viewers
- `device.json`: device and app details

The note is redacted with the same rules as captured text. The tester picks the destination in the share sheet. Keep does not send anything itself.

### What is stored, and what is not

- **Logs and network transactions** are kept in memory only, capped at `memoryCapacity` and `networkCapacity`. Killing the app clears them.
- **Crash snapshot.** On an uncaught Objective-C exception, Keep writes the session to `Application Support/Keep/crash-snapshot.bin`. The file is AES-GCM encrypted with a 256-bit key in the Keychain (`AfterFirstUnlockThisDeviceOnly`), excluded from backup, and written with complete file protection. The next launch reads it, deletes it, and offers it as *Share crashed session*.
- **Redaction** runs before anything is stored. It covers bearer and basic credentials, JWTs, `Authorization`, `Cookie` and `X-Api-Key` headers, URL credentials and sensitive query values, sensitive JSON keys, emails, E.164 phone numbers, SSNs, and card numbers that pass the Luhn check. The same rules apply to error text, to the note in a report, and to the user identifier the app sets. Keys are matched by token, so `authorization_token` and `apiKey` are redacted and `author` is not. Use `allowedKeys` for values you need to see, and `extraKeys` or `extraPatterns` for your own.

### Limits

- **OSLog.** Keep captures swift-log. Direct `os.Logger` and `os_log` calls cannot be intercepted, so route logging through swift-log.
- **Signal crashes** such as `EXC_BAD_ACCESS` are not captured. MetricKit reports them on the next launch (iOS 14+).
- **Redaction is pattern-based.** Keep cannot know that a value in a custom format is sensitive. Add `extraPatterns` for those.

## Contributing

Issues and pull requests are welcome. If you are planning a larger change, open an issue first so we can discuss the approach.

1. Fork the repository.
2. Create a feature branch from `develop`: `git checkout -b feature/my-feature develop`.
3. Commit and push: `git commit -m "Add my feature"` followed by `git push origin feature/my-feature`.
4. Open a pull request into `develop` describing the change and the motivation behind it. `main` only receives release PRs.

Before opening a pull request, run `swift test`, `sh Scripts/keep-verify-excluded.test.sh`, and `xcodebuild -scheme Keep -destination 'generic/platform=iOS Simulator' build`.

## Contributors

<a href="https://github.com/theamiro">
    <img src="https://github.com/theamiro.png?size=96" alt="@theamiro avatar" width="72" height="72" />
    <br />
    <sub>@theamiro</sub>
</a>

## License

Keep is available under the MIT License. See [LICENSE](LICENSE) for the full text.

---

Made with ❤️ by [@theamiro](https://github.com/theamiro)
