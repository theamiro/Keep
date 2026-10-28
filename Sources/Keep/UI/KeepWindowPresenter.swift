#if canImport(UIKit)
    import UIKit

    /// Shows Keep in its own window above the app, so it works from any screen, over alerts and full-screen flows.
    /// The window is hidden while the app is inactive, so the app-switcher snapshot never shows Keep.
    @MainActor
    final class KeepWindowPresenter {
        static let shared = KeepWindowPresenter()

        private let container = KeepContainerViewController()
        private var window: UIWindow?
        private var isOpen = false
        private var previousKeyWindow: UIWindow?

        func start(shakeEnabled: Bool) {
            if shakeEnabled {
                ShakeGesture.install { [weak self] scene in self?.showMenu(in: scene) }
            }
            let center = NotificationCenter.default
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.appWillResignActive() }
            }
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.appDidBecomeActive() }
            }
        }

        // MARK: Entry points

        /// Opens the shake menu in `scene`, or in the foreground scene when no scene is given.
        func showMenu(in scene: UIWindowScene? = nil) {
            guard !isOpen, Keep.isEnabled else { return }
            open(in: scene)
            let menu = UIAlertController(title: "Keep", message: nil, preferredStyle: .actionSheet)
            if KeepRuntime.shared.current?.previousSnapshot != nil {
                menu.addAction(
                    UIAlertAction(title: "Share crashed session", style: .default) { [weak self] _ in
                        Task { @MainActor in self?.shareReport(scope: .crashedSession, closeWhenFinished: true) }
                    })
            }
            menu.addAction(
                UIAlertAction(title: "Share report", style: .default) { [weak self] _ in
                    Task { @MainActor in self?.shareReport(scope: .currentSession, closeWhenFinished: true) }
                })
            menu.addAction(
                UIAlertAction(title: "Log viewer", style: .default) { [weak self] _ in
                    Task { @MainActor in self?.presentViewer() }
                })
            for tool in KeepRuntime.shared.current?.registeredTools ?? [] {
                menu.addAction(
                    UIAlertAction(title: tool.title, style: .default) { [weak self] _ in
                        Task { @MainActor in
                            // Hide Keep first so the tool presents over the app, not over Keep.
                            self?.close()
                            tool.action()
                        }
                    })
            }
            menu.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                    Task { @MainActor in self?.close() }
                })
            menu.popoverPresentationController?.sourceView = container.view
            menu.popoverPresentationController?.sourceRect = CGRect(
                x: container.view.bounds.midX, y: container.view.bounds.midY, width: 1, height: 1
            )
            container.present(menu, animated: true)
        }

        func showViewer() {
            guard Keep.isEnabled else { return }
            if isOpen, container.presentedViewController != nil {
                return
            }
            open(in: nil)
            presentViewer()
        }

        /// Called when a viewer is dismissed, however it was presented.
        func viewerDismissed() {
            guard container.presentedViewController == nil else { return }
            close()
        }

        // MARK: Private

        private func presentViewer() {
            let viewer = KeepViewerViewController()
            viewer.modalPresentationStyle = .fullScreen
            container.present(viewer, animated: true)
        }

        private func shareReport(scope: KeepExportScope, closeWhenFinished: Bool) {
            KeepShareFlow.start(from: container, scope: scope) { [weak self] in
                if closeWhenFinished {
                    self?.close()
                }
            }
        }

        private func open(in scene: UIWindowScene?) {
            let target = scene ?? Self.foregroundScene()
            // A window belongs to one scene. When the shake comes from another scene, move the container there.
            if window == nil || window?.windowScene !== target {
                window?.isHidden = true
                window?.rootViewController = nil
                window = makeWindow(in: target)
            }
            previousKeyWindow = currentKeyWindow()
            isOpen = true
            window?.isHidden = false
            window?.makeKeyAndVisible()
        }

        private func close() {
            isOpen = false
            if container.presentedViewController != nil {
                container.dismiss(animated: false)
            }
            window?.isHidden = true
            previousKeyWindow?.makeKey()
            previousKeyWindow = nil
        }

        private func appWillResignActive() {
            guard isOpen else { return }
            window?.isHidden = true
        }

        private func appDidBecomeActive() {
            guard isOpen, let window else { return }
            window.isHidden = false
            window.makeKeyAndVisible()
        }

        private static func foregroundScene() -> UIWindowScene? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        }

        private func makeWindow(in scene: UIWindowScene?) -> UIWindow {
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            window.rootViewController = container
            return window
        }

        private func currentKeyWindow() -> UIWindow? {
            let sceneWindows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return sceneWindows.first { $0.isKeyWindow && $0 !== window }
                ?? UIApplication.shared.windows.first { $0.isKeyWindow && $0 !== window }
        }
    }

    /// The root of Keep's window. It only hosts presentations.
    final class KeepContainerViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }
    }
#endif
