#if canImport(UIKit)
    import SwiftUI

    /// Dense network row with method, status, path, host and response size.
    struct NetworkRow: View {
        let transaction: KeepHTTPTransaction

        var body: some View {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        KeepPill(text: transaction.method.uppercased(), color: Color(uiColor: .systemIndigo))
                        KeepPill(
                            text: transaction.statusCode.map(String.init) ?? "ERR",
                            color: Color(uiColor: KeepTheme.statusColor(transaction.statusCode))
                        )
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0f ms", transaction.duration * 1000))
                            Text(transaction.responseBody.map { ByteCountDisplay.string($0.byteCount) } ?? "—")
                        }
                        .keepCodeFont(size: 10)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    }
                    Text(transaction.displayPath.isEmpty ? "/" : transaction.displayPath)
                        .keepCodeFont(size: 12, weight: .medium)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(hostLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let error = transaction.errorDescription {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(transaction.errorDescription == nil ? Color.clear : Color.red.opacity(0.055))
        }

        private var hostLine: String {
            let host = URLComponents(string: transaction.url)?.host ?? transaction.url
            return [host, KeepTheme.rowTimeFormatter.string(from: transaction.startedAt), transaction.label]
                .joined(separator: " · ")
        }
    }

    #if DEBUG
        #Preview {
            VStack(spacing: 0) {
                ForEach(PreviewSamples.transactions) { transaction in
                    NetworkRow(transaction: transaction)
                    Divider()
                }
            }
        }
    #endif
#endif
