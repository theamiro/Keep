# 2. SwiftUI views inside UIKit controllers

Date: 2026-10-28

## Status

Accepted

## Context

The viewer was all UIKit: hand-built `UIStackView` cells, `UILabel` subclasses for pills, and Auto Layout code for every section of the detail screens. Changing how a row or section looks meant reading layout code and running the app to see it. Xcode previews would make that faster, but `#Preview` for a `UIViewController` needs iOS 17, and the deployment floor is iOS 15.

A full SwiftUI rewrite would have to replace things UIKit does well here, and on iOS 15 it would also lose `NavigationStack` and `@Observable`:

- The lists update several times a second while the app logs. The diffable table views handle that well.
- Keep shows itself in its own `UIWindow` so it works in any host app.
- JSON bodies use Runestone, which is a UIKit text view.

## Decision

- Views Keep draws itself (rows, pills, key-value lists, section content, empty states) are SwiftUI, in `Sources/Keep/UI/Components`.
- View controllers, table views, navigation, the search controller, Keep's window, the share sheet and the Runestone code block stay UIKit.
- `UI/KeepHosting.swift` joins the two:
  - `KeepHostingCell<Content>` shows a SwiftUI row in a table view cell. It uses `UIHostingConfiguration` on iOS 16 and later, and a hosting controller it measures itself on iOS 15.
  - `KeepHostingView<Content>` shows a SwiftUI view in UIKit layout. It measures its height for the width it is given. A view whose own state changes its height calls `keepInvalidateSize` from the environment.
- SwiftUI views have `#Preview`s with sample data from `UI/PreviewSamples.swift`. Controllers get `@available(iOS 17, *) #Preview`s. Both are compiled only in Debug.

## Consequences

- Rows and sections can be changed and checked in Xcode previews without running the app.
- Previews of view controllers only run on an iOS 17 or later simulator. This is fine because previews are a development tool.
- The selectable log message stays a `UITextView`, because SwiftUI's `textSelection` cannot select part of the text on iOS.
- The iOS 15 path in `KeepHostingCell` can be deleted when the floor reaches iOS 16.
- New custom UI goes in SwiftUI. A new screen still starts as a UIKit controller unless a later ADR changes this.
