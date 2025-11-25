//
//  LogMetadataView.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

#if canImport(UIKit)
import SwiftUI
import Logging

struct LogMetadataView: View {
    var metadata: Logger.Metadata
    var body: some View {
        VStack {
            HStack {
                TitleHeaderView(title: "Metadata")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copyToPasteboard(metadata.description)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            let data = try encoder.encode(metadata)
            return String(decoding: data, as: UTF8.self)
        } catch {
            assertionFailure("Failed to encode metadata for display: \(error)")
            return "{}"
        }
    }
}

@available(iOS 17.0, *)
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
#endif
