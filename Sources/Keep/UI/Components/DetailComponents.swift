#if canImport(UIKit)
    import SwiftUI

    /// The small uppercase heading above each section of a detail screen.
    struct KeepSectionHeading: View {
        let title: String

        var body: some View {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A detail screen section: a heading, then its content at full width.
    struct KeepDetailSection<Content: View>: View {
        let title: String
        let content: Content

        init(title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                KeepSectionHeading(title: title)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Secondary text inside a section, such as "No body".
    struct KeepNote: View {
        let text: String
        var font: Font = .subheadline

        var body: some View {
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Centred message shown behind an empty list.
    struct KeepEmptyState: View {
        let message: String

        var body: some View {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The text before JSON embedded in a string, shown above the JSON's code block.
    struct CodeBlockPrefix: View {
        let text: String

        var body: some View {
            Text(text)
                .keepCodeFont(size: 11)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Level and full timestamp above a log entry's message.
    struct LogDetailHeader: View {
        let entry: LogEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                KeepPill(text: entry.level.shortCode, color: entry.level.color)
                Text(KeepCodec.displayString(for: entry.timestamp))
                    .keepCodeFont(size: 11)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Method, status and duration at the top of a network transaction's overview.
    struct TransactionSummary: View {
        let transaction: KeepHTTPTransaction

        var body: some View {
            HStack(spacing: 8) {
                KeepPill(text: transaction.method.uppercased(), color: Color(uiColor: .systemIndigo))
                KeepPill(
                    text: transaction.statusCode.map(String.init) ?? "ERR",
                    color: Color(uiColor: KeepTheme.statusColor(transaction.statusCode))
                )
                Spacer(minLength: 0)
                Text(String(format: "%.0f ms", transaction.duration * 1000))
                    .keepCodeFont(size: 11)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A header count that expands into the header list. Collapsed by default because headers are often long.
    struct HeadersDisclosure: View {
        let headers: [String: String]
        @State private var isExpanded = false
        @Environment(\.keepInvalidateSize) private var invalidateSize

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isExpanded.toggle()
                    invalidateSize()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(headers.count) headers")
                            .font(.subheadline)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Hides the headers" : "Shows the headers")

                if isExpanded {
                    KeyValueList(rows: headers.keys.sorted().map { KeepKeyValue($0, headers[$0] ?? "") })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #if DEBUG
        #Preview("Log detail parts") {
            VStack(spacing: 18) {
                KeepDetailSection(title: "Message") {
                    LogDetailHeader(entry: PreviewSamples.error)
                    Text(PreviewSamples.error.message)
                }
                KeepDetailSection(title: "Body") {
                    KeepNote(text: "No body")
                }
            }
            .padding()
        }

        #Preview("Network detail parts") {
            VStack(spacing: 18) {
                KeepDetailSection(title: "Transaction") {
                    TransactionSummary(transaction: PreviewSamples.clientError)
                }
                KeepDetailSection(title: "Headers") {
                    HeadersDisclosure(headers: PreviewSamples.success.requestHeaders)
                }
            }
            .padding()
        }

        #Preview("Empty state") {
            KeepEmptyState(message: "No logs match the search or level.")
        }
    #endif
#endif
