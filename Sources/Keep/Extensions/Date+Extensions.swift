//
//  Date+Extensions.swift
//  Keep
//
//  Created by Michael Amiro on 22/04/2025.
//

import Foundation

extension Date {
    func ISO8601Format() -> String {
        return Formatter.iso8601.string(from: self)
    }
    func formatted() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy, HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }
}
