//
//  KeepCoordinator.swift
//  Keep
//
//  Created by Michael Amiro on 29/04/2025.
//

import UIKit

class KeepCoordinator {
    var navigationController: UINavigationController?

    init(navigationController: UINavigationController? = nil) {
        self.navigationController = navigationController
    }

    @MainActor
    func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    @MainActor
    func present(_ viewController: UIViewController) {
        navigationController?.present(viewController, animated: true)
    }
}
