import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

func copyToPasteboard(_ value: String, completion: () -> Void) {
#if canImport(UIKit)
    UIPasteboard.general.string = value
    completion()
#elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    completion()
#endif
}
