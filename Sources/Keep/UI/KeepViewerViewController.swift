#if canImport(UIKit)
    import UIKit

    /// The log viewer: a tab bar with Logs and Network. Built from any screen via `Keep.present()` or `Keep.makeViewer()`.
    final class KeepViewerViewController: UITabBarController {
        init() {
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            guard let core = KeepRuntime.shared.current, core.isEnabled else {
                viewControllers = [KeepPlaceholderViewController(message: "Keep is not running in this build.")]
                return
            }
            let logs = UINavigationController(rootViewController: LogListViewController(core: core))
            logs.tabBarItem = UITabBarItem(title: "Logs", image: UIImage(systemName: "doc.text"), tag: 0)
            let network = UINavigationController(rootViewController: NetworkListViewController(core: core))
            network.tabBarItem = UITabBarItem(title: "Network", image: UIImage(systemName: "arrow.left.arrow.right"), tag: 1)
            viewControllers = [logs, network]
        }

        /// Dismisses the viewer. Used by the Done button on both tabs.
        func closeViewer() {
            dismiss(animated: true) {
                KeepWindowPresenter.shared.viewerDismissed()
            }
        }
    }

    final class KeepPlaceholderViewController: UIViewController {
        private let message: String

        init(message: String) {
            self.message = message
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = message
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
            ])
        }
    }

    /// Shared navigation items for the two list screens: Done, Share and Clear.
    class KeepListViewController: UITableViewController {
        let core: KeepCore

        init(core: KeepCore) {
            self.core = core
            super.init(style: .plain)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
            )
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped)),
                UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(clearTapped))
            ]
        }

        @objc func doneTapped() {
            (tabBarController as? KeepViewerViewController)?.closeViewer()
        }

        @objc func shareTapped() {
            KeepShareFlow.start(from: tabBarController ?? self, scope: .currentSession, onFinish: {})
        }

        @objc func clearTapped() {
            let alert = UIAlertController(
                title: "Clear session",
                message: "Removes all logs and network transactions from this session. This cannot be undone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
                Task { @MainActor in self?.core.clearSession() }
            })
            present(alert, animated: true)
        }
    }
#endif
