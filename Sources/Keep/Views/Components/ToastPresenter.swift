#if canImport(UIKit)
//
//  ToastPresenter.swift
//  Keep
//
//  Created by Michael Amiro on 25/11/2025.
//

import UIKit
import SwiftUI

@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private struct ToastEntry {
        let hostingController: UIHostingController<PopupView>
        let containerView: UIView
        let bottomConstraint: NSLayoutConstraint
    }

    private var toasts: [ToastEntry] = []

    private let baseBottomInset: CGFloat = 32
    private let verticalSpacing: CGFloat = 56
    private let showDuration: TimeInterval = 0.35
    private let hideDuration: TimeInterval = 0.25

    private init() {}

    func show(
        message: String,
        duration: TimeInterval = 5.0,
        in window: UIWindow?
    ) {
        guard let window = window ?? keyWindow else { return }
        let hosting = UIHostingController(rootView: PopupView(message: message))
        hosting.view.backgroundColor = .clear

        guard let container = hosting.view else {
            return
        }
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: 20)

        window.addSubview(container)

        let index = toasts.count
        let bottomConstraint = container.bottomAnchor.constraint(
            equalTo: window.safeAreaLayoutGuide.bottomAnchor,
            constant: baseBottomInset + 120
        )

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            bottomConstraint
        ])

        window.layoutIfNeeded()

        let entry = ToastEntry(
            hostingController: hosting,
            containerView: container,
            bottomConstraint: bottomConstraint
        )
        toasts.append(entry)

        layoutToasts(in: window, animated: true)

        UIView.animate(
            withDuration: showDuration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut]
        ) {
            container.alpha = 1
            container.transform = .identity
            window.layoutIfNeeded()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await self.dismiss(entry: entry, animated: true)
        }
    }

    private func layoutToasts(in window: UIWindow, animated: Bool) {
        guard !toasts.isEmpty else { return }

        for (index, entry) in toasts.enumerated() {
            entry.bottomConstraint.constant = -(baseBottomInset + CGFloat(index) * verticalSpacing)
        }

        if animated {
            UIView.animate(withDuration: 0.25) {
                window.layoutIfNeeded()
            }
        } else {
            window.layoutIfNeeded()
        }
    }

    private func dismiss(entry: ToastEntry, animated: Bool) async {
        guard let index = toasts.firstIndex(where: { $0.containerView === entry.containerView }) else { return }

        let window = entry.containerView.window

        let removeBlock = {
            entry.containerView.removeFromSuperview()
        }

        if animated {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                UIView.animate(withDuration: self.hideDuration, animations: {
                    entry.containerView.alpha = 0
                    entry.containerView.transform = CGAffineTransform(translationX: 0, y: 20)
                }, completion: { _ in
                    removeBlock()
                    continuation.resume()
                })
            }
        } else {
            removeBlock()
        }

        toasts.remove(at: index)

        if let window {
            layoutToasts(in: window, animated: true)
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
#endif
