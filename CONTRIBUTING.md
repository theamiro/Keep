# Contributing to Keep

Thank you for taking the time to improve Keep. The project follows the norms used across popular Swift packages: be respectful, prefer discussion-friendly issues, and keep every change reproducible. This document explains how to report problems, propose ideas, and submit pull requests that can be reviewed quickly.

## How to Get Help

- **Search first** – look through existing issues and pull requests for similar reports before opening a new one.
- **Use the right channel** – bugs and feature requests belong in GitHub issues; security reports should be emailed to the maintainers instead of being filed publicly.
- **Offer context** – share the platform, deployment target, Keep version/commit, and whether you are using the Swift Package directly or the sample app.

## Development Environment

| Tool | Version |
| --- | --- |
| Swift | 6.0 (per `// swift-tools-version`) |
| Xcode | 15.4 or newer (to build the iOS example and run UI previews) |
| Platforms | iOS 13+, macOS 11+ |

### Clone and Build

```bash
git clone https://github.com/theamiro/Keep.git
cd Keep
swift build
```

Open `Package.swift` directly in Xcode or double-click `KeepiOSExample/KeepiOSExample.xcodeproj` to run the sample application.

## Coding Standards

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/). Prefer clarity over brevity and keep public APIs documented with `///` comments.
- Add or update automated tests in `Tests/KeepTests` whenever you touch behavior.
- Keep dependencies minimal—`swift-log` is the only external package today. Discuss new dependencies in an issue before opening a PR.
- Ensure new log surface areas remain privacy aware (sensitive keys should be redacted before persistence or display).
- Update `ReadME.md` and the sample app when you introduce public-facing changes so users can discover them.

## Workflow for Code Changes

1. **Fork & branch** – work off a fork and use descriptive branch names such as `feature/file-backed-rotation`.
2. **Develop incrementally** – keep commits focused; each commit should build and pass tests.
3. **Run the test suite** – `swift test` must pass, and `swift build -c release` is encouraged for API or performance changes. When touching the UIKit browser, also verify `KeepiOSExample` in the iOS Simulator via `xcodebuild -scheme KeepiOSExample -destination 'platform=iOS Simulator,name=iPhone 15' build`.
4. **Document migrations** – if your change requires manual steps (for example, schema updates or configuration switches), describe them in the PR description.
5. **Open a pull request** – include context, screenshots for UI changes, and link to related issues. Highlight any backwards-incompatible changes at the top of the PR body.

## Reporting Bugs

- Provide a minimal reproduction snippet or attach a runnable sample project.
- Share the expected behavior, the actual result, and any crash logs or console output (redact sensitive data first).
- Mention whether you tested against the latest `main` branch.

## Feature Requests

- Explain the user problem the feature solves rather than the specific implementation.
- Note any existing APIs that are insufficient.
- Call out potential privacy or performance implications so they can be weighed early.

## Documentation and Examples

Enhancements to the documentation are first-class contributions. Updates to `ReadME.md`, inline `///` docs, and the UIKit log browser in `KeepiOSExample` often help others more than code alone. If you add a new capability, consider supplying demo entries in `KeepiOSExample` so reviewers can manually test it.

## License

By contributing, you agree that your contributions will be licensed under the MIT License, the same as the rest of the project. Make sure any new third-party assets are compatible with MIT licensing.

Thanks again for improving Keep!
