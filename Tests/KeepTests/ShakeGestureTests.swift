#if canImport(UIKit)
    @testable import Keep
    import Testing
    import UIKit

    /// Records the motion events UIKit forwards to it.
    private final class MotionRecorder: UIResponder {
        var endedMotions: [UIEvent.EventSubtype] = []

        override func motionEnded(_ motion: UIEvent.EventSubtype, with _: UIEvent?) {
            endedMotions.append(motion)
        }
    }

    /// A window whose next responder is a recorder, standing in for the window scene.
    private final class ForwardingWindow: UIWindow {
        let recorder = MotionRecorder()

        override var next: UIResponder? {
            recorder
        }
    }

    /// Installs the process-wide shake handler, so it is the only suite that does.
    @Suite("Shake gesture", .serialized)
    @MainActor
    struct ShakeGestureTests {
        @Test func shakesStillReachTheNextResponderAndOpenKeep() async throws {
            var shakes = 0
            ShakeGesture.install { _ in shakes += 1 }

            let window = ForwardingWindow(frame: .zero)
            // Before 0.1.1 UIKit forwarded this as keep_motionEnded:with:, which the next responder does not implement.
            window.motionEnded(.motionShake, with: nil)

            #expect(window.recorder.endedMotions == [.motionShake])
            for _ in 0..<40 where shakes == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(shakes == 1)
        }

        @Test func otherMotionsAreForwardedWithoutOpeningKeep() async throws {
            var shakes = 0
            ShakeGesture.install { _ in shakes += 1 }

            let window = ForwardingWindow(frame: .zero)
            window.motionEnded(.none, with: nil)

            #expect(window.recorder.endedMotions == [UIEvent.EventSubtype.none])
            try await Task.sleep(nanoseconds: 50_000_000)
            #expect(shakes == 0)
        }
    }
#endif
