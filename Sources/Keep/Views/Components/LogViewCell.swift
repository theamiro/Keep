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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "document.fill")
                        .font(.system(size: 10))
                    Text("\(log.file):\(log.line)")
                        .font(.system(size: 10))
                }
            }
            .foregroundColor(Color.secondary)
            HStack(alignment: .top) {
                Text(String(log.description.prefix(140)))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(log.level.rawValue.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .background(log.level.color.opacity(0.2))
                    .clipShape(.capsule)
            }
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10.0))
                    .foregroundColor(Color.secondary)
                Text(log.tag.title.uppercased())
                    .font(.custom("Menlo", size: 10.0))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4.0))
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
    LogViewCell(log: Log(id: "647474", level: .info, description: "Something crazy went wrong", timestamp: Date(), metadata: [
        "url": .string("https://api.example.com"),
        "method": .string("GET"),
        "headers": .dictionary([
            "Authorization": .string("Bearer ***"),
            "Content-Type": .string("application/json")
        ])
    ], source: "Somewhere"))
    LogViewCell(log: Log(id: "847474", level: .trace, description: "LogViewModel deinit", timestamp: Date(), metadata: nil, source: "Somewhere"))
}
