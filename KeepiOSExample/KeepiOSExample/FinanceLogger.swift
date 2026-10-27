//
//  FinanceLogger.swift
//  KeepiOSExample
//
//  Created for the Keep finance sample app.
//

import Foundation
import Logging

enum FinanceLogger {
    private static let subsystem = "com.keep.examples.finance"

    static var dashboard: Logger = {
        var logger = Logger(label: "\(subsystem).dashboard")
        logger[metadataKey: "component"] = "dashboard"
        return logger
    }()

    static var networking: Logger = {
        var logger = Logger(label: "\(subsystem).networking")
        logger[metadataKey: "component"] = "networking"
        return logger
    }()

    static var scheduler: Logger = {
        var logger = Logger(label: "\(subsystem).scheduler")
        logger[metadataKey: "component"] = "scheduler"
        return logger
    }()
}
