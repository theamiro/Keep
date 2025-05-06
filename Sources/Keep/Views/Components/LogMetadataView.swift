//
//  LogMetadataView.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import SwiftUI
import Logging

@available(iOS 13.0, *)
struct LogMetadataView: View {
    var metadata: Logger.Metadata
    var body: some View {
        VStack {
            HStack {
                TitleHeaderView(title: "Metadata")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UIPasteboard.general.string = metadata.description
                } label: {
                    Text("Copy")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Text(metadataToJsonString)
                .font(.custom("Menlo", size: 12))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8.0))
        }
        .padding()
    }

    var metadataToJsonString: String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try jsonEncoder.encode(metadata)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            print("Error encoding metadata: \(error)")
        }
        return "{}"
    }
}

@available(iOS 13.0, *)
#Preview {
    LogMetadataView(metadata: [
        "url": .string("https://api.example.com"),
        "method": .string("GET"),
        "headers": .dictionary([
            "Authorization": .string("Bearer ***"),
            "Content-Type": .string("application/json")
        ])
    ])
}
