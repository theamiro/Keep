//
//  String+Extensions.swift
//  Keep
//
//  Created by Michael Amiro on 22/04/2025.
//

import Foundation

extension String {
    var iso8601Date: Date? {
        return Formatter.iso8601.date(from: self) ?? Formatter.iso8601.date(from: self)
    }
}
