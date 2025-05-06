//
//  LogViewCell.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import SwiftUI

@available(iOS 13.0, *)
struct LogViewCell: View {
    var log: Log
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text(String(log.description.prefix(140)))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(log.level.rawValue.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(log.level.color.opacity(0.2))
                    .clipShape(.capsule)
            }
            Group {
                if #available(iOS 17.0, *) {
                    Text(log.timestamp.formatted())
                        .foregroundStyle(.secondary)
                } else {
                    Text(log.timestamp.formatted())
                        .foregroundColor(Color.secondary)
                }
            }
            .font(.system(size: 12.0))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

@available(iOS 13.0, *)
#Preview("Log View Cell") {
    LogViewCell(log: Log(id: "747474", level: .critical, description: "Something crazy went wrong", timestamp: Date(), metadata: nil, source: "Somewhere"))
}
