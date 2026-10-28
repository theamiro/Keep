//
//  AppDelegate.swift
//  KeepiOSExample
//
//  Created by Michael Amiro on 28/09/2025.
//

import Logging
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureLogging()
        return true
    }

    private func configureLogging() {
        Diagnostics.start()

        LoggingSystem.bootstrap { label in
            var consoleHandler = StreamLogHandler.standardOutput(label: label)
            consoleHandler.logLevel = .info

            return MultiplexLogHandler([consoleHandler] + Diagnostics.logHandlers(label: label))
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_: UIApplication, didDiscardSceneSessions _: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
