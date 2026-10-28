# Keep iOS Example

This sample finance dashboard app demonstrates how to embed the Keep runtime log viewer in a UIKit project, multiplex log handlers, and showcase different logging use cases (networking, UI lifecycle, background timers).

## Requirements

- Xcode 15 or newer
- iOS 15.0 deployment target (can run on the simulator or a device)
- Swift 5.9 toolchain (Keep targets Swift Concurrency)

## Run the Demo

1. Open `KeepiOSExample/KeepiOSExample.xcodeproj` in Xcode.
2. Select the `KeepiOSExample` scheme and your preferred destination (simulator or device).
3. Build & run. The dashboard will start auto-logging and you can tap **Open Keep Log Viewer** to inspect the captured entries.

## Implementation Examples

### 1. Start Keep and Multiplex Handlers

`AppDelegate.configureLogging()` starts Keep through `Diagnostics` and keeps console logging enabled for local debugging. `Diagnostics.swift` is the only file that imports Keep. Its methods compile to no-ops in builds without the `KEEP_ENABLED` condition.

```swift
private func configureLogging() {
    Diagnostics.start()

    LoggingSystem.bootstrap { label in
        var consoleHandler = StreamLogHandler.standardOutput(label: label)
        consoleHandler.logLevel = .info

        return MultiplexLogHandler([consoleHandler] + Diagnostics.logHandlers(label: label))
    }
}
```

In this project, Debug has `KEEP_ENABLED` and Release excludes Keep's object file (`EXCLUDED_SOURCE_FILE_NAMES = Keep.o`). A Run Script phase, `Scripts/keep-verify-excluded.sh`, fails the Release build if Keep is still linked.

### 2. Create Domain-Specific Loggers

`FinanceLogger` exposes namespaced `Logger` instances to keep metadata consistent and filterable:

```swift
enum FinanceLogger {
    private static let subsystem = "com.keep.examples.finance"

    static var dashboard: Logger = {
        var logger = Logger(label: "\(subsystem).dashboard")
        logger[metadataKey: "component"] = "dashboard"
        return logger
    }()
}
```

Each module (`dashboard`, `networking`, `scheduler`) gets its own logger so the Keep viewer can group entries by `component`.

### 3. Open the Log Viewer

Shake the device on any screen to open the shake menu. The **Open Keep Log Viewer** button calls `Diagnostics.present()`, which opens the viewer in Keep's own window. Keep does not depend on the screen the button is on, so the same call works from the splash screen or a login screen.

```swift
@objc private func openLogsTapped() {
    FinanceLogger.dashboard.trace("Presenting Keep log viewer")
    Diagnostics.present()
}
```

### 4. Log Networking State with Metadata

`FinanceAPIClient` produces rich metadata for each mocked network call, highlighting why Keep is useful during QA:

```swift
logger.notice("Starting mocked transaction fetch", metadata: [
    "url": .string(url.absoluteString),
    "request_id": .string(requestID),
    "mocked": .string("true")
])

logger.info("Mocked transaction fetch succeeded", metadata: [
    "status": .string(String(httpResponse.statusCode)),
    "latency_ms": .string(latencyMS)
])
```

Switch the `limit` parameter or simulate failures to watch the Keep viewer update in real time.

## Screenshots

Drop PNG or JPEG files inside `KeepiOSExample/docs/screenshots/` (create the folder if needed) and update the table below so teammates can visualize the flow.

| Dashboard | Keep Log Viewer |
| --- | --- |
| ![Dashboard placeholder](docs/screenshots/dashboard.png) | ![Log viewer placeholder](docs/screenshots/log-viewer.png) |

> Replace the placeholder filenames once screenshots have been captured.

## Project Layout

- `KeepiOSExample/AppDelegate.swift` – Starts Keep and configures the log handlers.
- `KeepiOSExample/Diagnostics.swift` – The only file that imports Keep. Copy it into your own app (see `Templates/Diagnostics.swift`).
- `KeepiOSExample/ViewController.swift` – Finance dashboard UI, auto logging timer, and log viewer presentation.
- `KeepiOSExample/FinanceAPIClient.swift` – Mocked networking layer plus `URLProtocol` for sample payloads.
- `KeepiOSExample/FinanceLogger.swift` – Shared loggers with subsystem + component metadata.

Use this example as a reference when integrating Keep into your own UIKit or SwiftUI codebases.
