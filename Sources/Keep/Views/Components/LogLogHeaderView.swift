//
//  LogLogHeaderView.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import SwiftUI
import Logging

@available(iOS 13.0, *)
struct LogLogHeaderView: View {
    var log: Log
    var body: some View {
        VStack {
            TitleHeaderView(title: "Log Information")
            VStack {
                HStack {
                    Text(log.timestamp.formatted())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(log.level.rawValue.capitalized)
                        .font(.system(size: 12, weight: .semibold))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(log.level.color.opacity(0.2))
                        .clipShape(.capsule)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                Divider()
                HStack {
                    Text("Tag")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(log.tag.title)
                        .font(.system(size: 12, weight: .semibold))
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                Divider()
                VStack(alignment: .leading) {
                    if let source = log.source {
                        HStack {
                            Text("Source")
                                .fontWeight(.semibold)
                            Text(source)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 2)
                        Divider()
                    }
                    HStack {
                        Text("File")
                            .fontWeight(.semibold)
                        Text(log.file)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
                    Divider()
                    HStack {
                        Text("Function")
                            .fontWeight(.semibold)
                        Text(log.function)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                    Divider()
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Message")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = log.description
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
                        Text(log.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8.0))
        }
        .padding()
    }
}

@available(iOS 13.0, *)
#Preview {
    LogLogHeaderView(log: Log(id: "747474", level: .critical, description: "Something crazy went wrong", timestamp: Date(), metadata: [
        "url": .string("https://api.example.com"),
        "method": .string("GET"),
        "headers": .dictionary([
            "Authorization": .string("Bearer ***"),
            "Content-Type": .string("application/json")
        ])
    ], source: "Somewhere"))
}
