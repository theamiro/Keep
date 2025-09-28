//
//  AppDelegate.swift
//  KeepiOSExample
//
//  Created by Michael Amiro on 28/09/2025.
//

import UIKit
import Keep
import Logging

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureLogging()
        return true
    }

    private func configureLogging() {
        let configuration = KeepConfiguration(logHandler: .fileSystem("finance-demo-log.json"), logLevel: .trace)
        Keep.configure(with: configuration)

        LoggingSystem.bootstrap { label in
            var keepHandler = KeepLogHandler(configuration: configuration)
            keepHandler[metadataKey: "logger_label"] = .string(label)

            var consoleHandler = StreamLogHandler.standardOutput(label: label)
            consoleHandler.logLevel = .info

            return MultiplexLogHandler([keepHandler, consoleHandler])
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}
