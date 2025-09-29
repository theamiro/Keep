//
//  Tag.swift
//  Keep
//
//  Created by Michael Amiro on 29/09/2025.
//

import Foundation

enum Tag {
    case network
    case memory
    case unknown

    var title: String {
        switch self {
        case .network: "HTTP"
        case .memory: "Memory"
        case .unknown: "Unknown"
        }
    }
}
