//
//  ToastPresentable.swift
//  Keep
//
//  Created by Michael Amiro on 25/11/2025.
//

import UIKit

protocol ToastPresentable: AnyObject where Self: UIViewController {
    func showPopup(message: String, duration: TimeInterval)
}

extension ToastPresentable {
    func showPopup(message: String, duration: TimeInterval = 5.0) {
        ToastPresenter.shared.show(message: message, duration: duration, in: view.window)
    }
}
