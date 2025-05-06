//
//  In.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import Foundation

extension Int {
    var abbreviated: String {
        switch self {
        case 1_000_000_000_000...:
            return "\(self / 1_000_000_000_000)T"
        case 1_000_000_000...:
            return "\(self / 1_000_000_000)B"
        case 1_000_000...:
            return "\(self / 1_000_000)M"
        case 1_000...:
            return "\(self / 1_000)K"
        default:
            return "\(self)"
        }
    }
}
