# Keep – Privacy-Aware Log Viewer for Swift

<p align="left">
<img src="https://github.com/theamiro/Keep/actions/workflows/build.yml/badge.svg" />
<img src="https://img.shields.io/badge/platform-iOS-brightgreen" />
<a href="https://github.com/kefranabg/readme-md-generator/blob/master/LICENSE">
    <img alt="License: MIT"  src="https://img.shields.io/badge/license-MIT-yellow.svg"  target="_blank" />
</a>
</p>

**Keep** is a lightweight companion for apps that want to expose runtime logs to their users, customer-support agents, or QA teams without compromising privacy. It plugs into [swift-log](https://github.com/apple/swift-log), stores entries in memory or on disk, and ships with a UIKit log browser that can be embedded in any app or shared via a debug build.

## Why Keep?

- **User controlled** – expose logs behind a settings screen or support gesture so users decide when to share diagnostics.
- **Storage flexibility** – pick an ephemeral in-memory buffer for sensitive builds, or a durable file-backed store when you need persistence.
- **Productivity** – the supplied `FileLogViewController` groups pinned items, filters by level and tag, and makes it easy to triage issues.
- **Privacy aware** – metadata is automatically sanitised before it ever leaves the device, with extensible redaction rules you control.
- **Extensible tagging** – classify logs as HTTP, Memory, or any custom category by registering your own `LogTag` implementations.

## Getting Started

### Installation (Swift Package Manager)

Add Keep to your package manifest:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/theamiro/Keep.git", branch: "main")
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

### Configure Keep at Launch

```swift
import Keep
import Logging

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let configuration = KeepConfiguration(
        logHandler: .inMemoryCache,   // or .fileSystem("keep-log.json")
        logLevel: .debug,
        redactsSensitiveInformation: true
    )

    Keep.configure(with: configuration)

    LoggingSystem.bootstrap { _ in
        KeepLogHandler(configuration: configuration)
    }

    return true
}
```

- Use `.inMemoryCache` when you want logs to disappear on app restart or when you cannot write to disk (e.g. TestFlight or privacy-sensitive builds).
- Use `.fileSystem("log.json")` to persist entries under the app's documents directory. File names must not contain `/` or `..`.

### Present the Log Viewer

```swift
let logsViewController = Keep.logViewController()
let navigationController = UINavigationController(rootViewController: logsViewController)
window.rootViewController?.present(navigationController, animated: true)
```

`FileLogViewController` automatically sections pinned logs, supports swipe actions (pin/unpin and delete), and offers search, level filtering, and tag filtering.

### Pinning and Filtering

- Swipe right on any row to pin or unpin it. Pinned entries always appear in the dedicated "Pinned" section.
- Filter by `Logger.Level` using the control at the top of the screen.
- Filter by tag (HTTP, Memory, Unknown, or custom) using the tag filter.
- Search matches message text, metadata keys and values, source, file/function names, line number, and timestamp.

## Advanced Topics

### Log Storage Limits

File-backed storage is capped at **1,000 entries** by default. When the limit is reached the oldest entries are evicted automatically. Adjust the cap via `KeepConfiguration`:

```swift
KeepConfiguration(
    logHandler: .fileSystem("app.json"),
    maxLogCount: 500   // keep only the 500 most recent entries
)
```

### Custom Metadata Redaction

Keep automatically redacts common sensitive keys (`token`, `authorization`, `password`, `email`, etc.) and patterns (SSNs, credit card numbers, bearer tokens). You can extend this with your own keys and patterns:

```swift
KeepConfiguration(
    logHandler: .inMemoryCache,
    redactsSensitiveInformation: true,
    additionalSensitiveKeys: ["x-api-key", "session_id"],
    additionalSensitiveKeyFragments: ["internal_id"],
    additionalRedactionPatterns: [#"ORDER-\d+"#]
)
```

Set `redactsSensitiveInformation: false` only when inspecting raw metadata locally — never in production builds.

### Custom Log Tags

Logs are classified into categories — **HTTP**, **Memory**, or **Unknown** — using `LogTagService`. You can register your own tags to cover additional categories:

```swift
struct AnalyticsTag: LogTag {
    var title: String { "Analytics" }
    func matches(metadata: Logger.Metadata?, description: String) -> Bool {
        metadata?.matches("analytics") == true || description.lowercased().contains("analytics")
    }
}

let tagService = LogTagService()
tagService.register(AnalyticsTag())

Keep.configure(with: KeepConfiguration(
    logHandler: .inMemoryCache,
    tagService: tagService
))
```

Custom tags are evaluated before the built-in `UnknownTag` fallback. The first matching tag wins.

The built-in `NetworkTag` matches logs whose metadata contains keys or values referencing `http` or `url`. The built-in `MemoryTag` matches logs whose message contains lifecycle words (`init`, `deinit`, `deallocate`) as whole words — common words like "initialize" or "initialization" are intentionally excluded.

### Clearing Logs

Call `FileLogViewModel.clearLogs` or use the built-in trash button. For in-memory storage this empties the cache; for file-backed storage the JSON file is reset to empty.

### Extending the UI

`FileLogViewController` is UIKit-based, but its rows are rendered using SwiftUI hosting cells. You can fork the repo and swap in custom SwiftUI views for your branding or theming needs.

## Contributing

Issues and pull requests are welcome. If you are planning a larger change, open an issue first so we can discuss the approach.

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-feature`.
3. Commit and push: `git commit -m "Add my feature"` followed by `git push origin feature/my-feature`.
4. Open a pull request describing the change and the motivation behind it.

## License

Keep is available under the MIT License. See [LICENSE](LICENSE) for the full text.

---

Made with ❤️ by [@theamiro](https://github.com/theamiro)
