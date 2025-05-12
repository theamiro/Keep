# Swift Keep Library

<p align="left">
<img src="https://github.com/theamiro/Keep/actions/workflows/build.yml/badge.svg" />
<img src="https://img.shields.io/badge/platform-iOS-brightgreen" />
<a href="https://github.com/kefranabg/readme-md-generator/blob/master/LICENSE">
    <img alt="License: MIT"  src="https://img.shields.io/badge/license-MIT-yellow.svg"  target="_blank" />
</a>
</p>

**Keep** is a Swift library that provides user-controlled access to application logs. It helps with debugging while aligning with privacy regulations like GDPR. It supports both in-memory and file system log storage, enabling secure, user-friendly log management.

## Features

-   **User-Controlled Logging**: Gives users visibility and control over their logs.
-   **Multiple Storage Options**: Supports in-memory and file system-based log storage.
-   **GDPR-Friendly**: Built with user privacy in mind, ensuring compliance with regulations.
-   **Debugging Aid**: Facilitates better reporting and debugging through accessible logs.

## Installation

To add Keep to your Swift project, use **Swift Package Manager**.

### Swift Package Manager

Add the following to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/theamiro/Keep.git", from: "1.0.0")
]
```

Then add `Keep` as a dependency in your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Keep"]
)
```

Alternatively, in Xcode:

1. Go to **File > Add Packages...**
2. Enter: `https://github.com/theamiro/Keep`
3. Choose the latest version and add it to your project.

## Usage

Below is a basic example of how to use Keep:

```swift
import Keep

// Create a logger instance
let logger = KeepLogger()

// Log a message
logger.log("This is a debug message.");

// Retrieve logs
let logs = logger.retrieveLogs()

// Clear logs
logger.clearLogs()
```

> 📌 **Note**: API usage may vary depending on implementation. Check the source for advanced configuration and storage behavior.

## Contributing

Contributions are welcome!

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

Please open an issue to discuss major changes before implementation.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

Made with ❤️ by [@theamiro](https://github.com/theamiro)
