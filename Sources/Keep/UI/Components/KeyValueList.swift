#if canImport(UIKit)
    import SwiftUI

    struct KeepKeyValue: Sendable {
        let key: String
        let value: String

        init(_ key: String, _ value: String) {
            self.key = key
            self.value = value
        }
    }

    /// Rows of key and value in a bordered group. Long-press a value to copy it. Shows nothing when there are no rows.
    struct KeyValueList: View {
        let rows: [KeepKeyValue]

        var body: some View {
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    // Keys can repeat (query parameters), so rows are identified by position. The list never changes.
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider()
                        }
                        KeyValueRow(row: row)
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
                )
            }
        }
    }

    private struct KeyValueRow: View {
        let row: KeepKeyValue

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Text(row.key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 86, alignment: .leading)
                Text(row.value)
                    .keepCodeFont()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    copyToPasteboard(row.value) {}
                } label: {
                    Label("Copy Value", systemImage: "doc.on.doc")
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            KeyValueList(rows: [
                KeepKeyValue("Source", "Checkout"),
                KeepKeyValue("Location", "CheckoutViewModel.swift:88 · submitOrder()"),
                KeepKeyValue("Token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0")
            ])
            .padding()
        }
    #endif
#endif
