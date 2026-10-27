//
//  ToastPresentable.swift
//  Keep
//
//  Created by Michael Amiro on 25/11/2025.
//

#if canImport(UIKit)
import UIKit

protocol ToastPresentable: AnyObject where Self: UIViewController {
    func showPopup(message: String, duration: TimeInterval)
}

extension ToastPresentable {
    func showPopup(message: String, duration: TimeInterval = 5.0) {
        ToastPresenter.shared.show(message: message, duration: duration, in: view.window)
    }
}
#elseif canImport(AppKit)
import AppKit

protocol ToastPresentable: AnyObject where Self: NSViewController {
    func showPopup(message: String, duration: TimeInterval)
}

extension ToastPresentable {
    func showPopup(message: String, duration: TimeInterval = 5.0) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational

        if let window = view.window {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }
}
#else
protocol ToastPresentable: AnyObject {
    func showPopup(message: String, duration: TimeInterval)
}

extension ToastPresentable {
    func showPopup(message: String, duration: TimeInterval = 5.0) {
        _ = (message, duration)
    }
}
#endif
