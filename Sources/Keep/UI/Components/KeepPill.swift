#if canImport(UIKit)
    import SwiftUI

    /// A short monospaced label on a tinted, rounded background, such as a log level or HTTP status.
    struct KeepPill: View {
        let text: String
        let color: Color

        var body: some View {
            Text(text)
                .keepCodeFont(size: 11, weight: .semibold)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    #if DEBUG
        #Preview {
            HStack {
                KeepPill(text: "ERR", color: .red)
                KeepPill(text: "POST", color: Color(uiColor: .systemIndigo))
                KeepPill(text: "200", color: .green)
            }
        }
    #endif
#endif
