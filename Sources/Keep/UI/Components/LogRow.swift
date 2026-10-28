#if canImport(UIKit)
    import SwiftUI

    /// Dense log row with a level marker, time, source, message and a metadata summary.
    struct LogRow: View {
        let entry: LogEntry

        var body: some View {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        KeepPill(text: entry.level.shortCode, color: entry.level.color)
                        Text(KeepTheme.rowTimeFormatter.string(from: entry.timestamp))
                            .keepCodeFont(size: 11, weight: .medium)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer(minLength: 0)
                        Text(entry.source.isEmpty ? entry.label : entry.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Pinned")
                        }
                    }
                    Text(entry.message)
                        .font(.subheadline)
                        .lineLimit(3)
                    if let summary {
                        Text(summary)
                            .keepCodeFont(size: 10)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 13)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                entry.level.color.frame(width: 3)
            }
            .background(entry.level >= .error ? Color(uiColor: entry.level.backgroundTint) : .clear)
        }

        private var summary: String? {
            let tag = entry.tag == "Unknown" ? nil : entry.tag
            let text = [tag, metadataSummary].compactMap { $0 }.joined(separator: " · ")
            return text.isEmpty ? nil : text
        }

        private var metadataSummary: String? {
            guard !entry.metadata.isEmpty else { return nil }
            let key = entry.metadata.keys.sorted().first ?? "metadata"
            let data = try? KeepCodec.encoder().encode(entry.metadata)
            let count = data?.count ?? entry.metadata.reduce(0) { $0 + $1.key.utf8.count + $1.value.text.utf8.count }
            return "{ } \(key) · \(ByteCountDisplay.string(count))"
        }
    }

    #if DEBUG
        #Preview {
            VStack(spacing: 0) {
                ForEach(PreviewSamples.logs) { entry in
                    LogRow(entry: entry)
                    Divider()
                }
            }
        }
    #endif
#endif
