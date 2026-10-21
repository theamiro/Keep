#if canImport(UIKit)
    import ObjectiveC
    import UIKit

    /// Opens Keep on shake. Swizzles `UIWindow.motionEnded` once; the original implementation still runs.
    enum ShakeGesture {
        private nonisolated(unsafe) static var handler: (@MainActor () -> Void)?
        private nonisolated(unsafe) static var installed = false

        static func install(_ onShake: @escaping @MainActor () -> Void) {
            handler = onShake
            guard !installed else { return }
            installed = true

            let originalSelector = #selector(UIResponder.motionEnded(_:with:))
            let swizzledSelector = #selector(UIWindow.keep_motionEnded(_:with:))
            guard let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
                  let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector) else { return }
            if class_addMethod(
                UIWindow.self,
                originalSelector,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod)
            ) {
                class_replaceMethod(
                    UIWindow.self,
                    swizzledSelector,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod)
                )
            } else {
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }

        fileprivate static func shakeDetected() {
            guard let handler else { return }
            Task { @MainActor in handler() }
        }
    }

    extension UIWindow {
        /// After the swap this selector runs the original `motionEnded`, so calling it first keeps the app's behaviour.
        @objc func keep_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            keep_motionEnded(motion, with: event)
            if motion == .motionShake {
                ShakeGesture.shakeDetected()
            }
        }
    }
#endif
