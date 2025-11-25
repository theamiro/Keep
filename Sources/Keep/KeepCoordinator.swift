//
//  KeepCoordinator.swift
//  Keep
//
//  Created by Michael Amiro on 29/04/2025.
//

#if canImport(UIKit)
import UIKit

public class KeepCoordinator {
    public var navigationController: UINavigationController?

    public init(navigationController: UINavigationController? = nil) {
        self.navigationController = navigationController
    }

    @MainActor
    public func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    @MainActor
    public func present(_ viewController: UIViewController) {
        navigationController?.present(viewController, animated: true)
    }
}
#endif
