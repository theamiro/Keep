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
- **Productivity** – the supplied `FileLogViewController` groups pinned items, filters by level, and makes it easy to triage issues.
- **Privacy aware** – metadata is automatically sanitised for common sensitive keys before it ever leaves the device.

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
        redactsSensitiveInformation: true // set to false to inspect raw metadata
    )

    Keep.configure(with: configuration)

    LoggingSystem.bootstrap { _ in
        KeepLogHandler(configuration: configuration)
    }

    return true
}
```

- Use `.inMemoryCache` when you want logs to disappear on app restart or when you cannot write to disk (for example TestFlight or privacy-sensitive builds).
- Use `.fileSystem("log.json")` to persist entries under the app’s documents directory. Every call to `LogHandler.log` appends a JSON representation of the entry.

### Present the Log Viewer

```swift
let logsViewController = Keep.logViewController()
let navigationController = UINavigationController(rootViewController: logsViewController)
window.rootViewController?.present(navigationController, animated: true)
```

`FileLogViewController` automatically sections pinned logs, supports swipe actions (pin/unpin and delete), and offers search and level filtering.

### Pinning and Filtering

- Swipe right on any row to pin or unpin it. Pinned entries always appear in the dedicated “Pinned” section.
- Use the segmented control at the top of the screen to filter by `Logger.Level`.
- Searching matches fields such as message, metadata values, file/function names, and identifiers.

### SwiftUI Previews

`FileLogViewModel.preview` now feeds the view controller with the in-memory `SampleLogs.preview()` dataset so previews are independent of the bundled `log.json` file used elsewhere.

## Advanced Topics

### Custom Metadata

`KeepLogHandler` merges any metadata you attach through the standard swift-log APIs. Keys containing `token` or `authorization` are automatically redacted when logs are persisted or displayed. Set `KeepConfiguration.redactsSensitiveInformation` to `false` if you need to review unredacted metadata (for example when debugging locally).

### Clearing Logs

Call `FileLogViewModel.clearLogs` or use the built-in trash button. For in-memory storage this empties the cache; for file-backed storage the JSON file is reset.

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
