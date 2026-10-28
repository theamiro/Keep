#if canImport(UIKit)
    import ObjectiveC
    import UIKit

    /// Opens Keep on shake. Replaces `UIWindow.motionEnded` once; the previous implementation still runs.
    enum ShakeGesture {
        private typealias MotionEndedIMP = @convention(c) (UIWindow, Selector, UIEvent.EventSubtype, UIEvent?) -> Void

        private nonisolated(unsafe) static var handler: (@MainActor (UIWindowScene?) -> Void)?
        private nonisolated(unsafe) static var installed = false

        /// `onShake` receives the scene whose window received the shake, so Keep opens in that scene.
        static func install(_ onShake: @escaping @MainActor (UIWindowScene?) -> Void) {
            handler = onShake
            guard !installed else { return }
            installed = true

            let selector = #selector(UIResponder.motionEnded(_:with:))
            guard let method = class_getInstanceMethod(UIWindow.self, selector),
                  let superclass = class_getSuperclass(UIWindow.self) else { return }

            // UIKit forwards motion events to the next responder under `_cmd`, so the previous
            // implementation must run under the original selector. Exchanging selectors sent
            // `keep_motionEnded:with:` to the window scene, which crashed.
            var previousIMP: IMP?
            typealias Replacement = @convention(block) (UIWindow, UIEvent.EventSubtype, UIEvent?) -> Void
            let replacement: Replacement = { window, motion, event in
                // When UIWindow inherits the method, look it up on each call so later changes to the superclass apply.
                if let previous = previousIMP ?? class_getMethodImplementation(superclass, selector) {
                    unsafeBitCast(previous, to: MotionEndedIMP.self)(window, selector, motion, event)
                }
                if motion == .motionShake {
                    shakeDetected(from: window)
                }
            }
            let replacementIMP = imp_implementationWithBlock(replacement)
            if !class_addMethod(UIWindow.self, selector, replacementIMP, method_getTypeEncoding(method)) {
                previousIMP = method_setImplementation(method, replacementIMP)
            }
        }

        private static func shakeDetected(from window: UIWindow) {
            guard let handler else { return }
            Task { @MainActor in handler(window.windowScene) }
        }
    }
#endif
