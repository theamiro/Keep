#if canImport(UIKit) && KEEP_RUNESTONE
    import Runestone
#endif

#if canImport(UIKit)
    import Logging
    import SwiftUI
    import UIKit

    extension Logger.Level {
        var uiColor: UIColor {
            switch self {
            case .trace: return .systemGray
            case .debug: return UIColor(red: 0.4, green: 0.7, blue: 0.9, alpha: 1)
            case .info: return .systemGreen
            case .notice: return UIColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 1)
            case .warning: return .systemOrange
            case .error: return .systemRed
            case .critical: return UIColor(red: 0.8, green: 0.0, blue: 0.4, alpha: 1)
            }
        }

        var shortCode: String {
            switch self {
            case .trace: return "TRC"
            case .debug: return "DBG"
            case .info: return "INF"
            case .notice: return "NTC"
            case .warning: return "WRN"
            case .error: return "ERR"
            case .critical: return "CRT"
            }
        }

        var backgroundTint: UIColor {
            uiColor.withAlphaComponent(self >= .error ? 0.1 : 0.08)
        }

        var color: Color {
            Color(uiColor: uiColor)
        }
    }

    enum KeepTheme {
        /// Time of day on list rows, to the millisecond.
        @MainActor static let rowTimeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()

        static func codeFont(ofSize size: CGFloat = 12, weight: UIFont.Weight = .regular) -> UIFont {
            UIFontMetrics(forTextStyle: .footnote).scaledFont(
                for: UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            )
        }

        static func statusColor(_ status: Int?) -> UIColor {
            switch status {
            case let status? where (200..<300).contains(status): return .systemGreen
            case let status? where (300..<400).contains(status): return .systemBlue
            case let status? where (400..<500).contains(status): return .systemOrange
            default: return .systemRed
            }
        }
    }

    /// The SwiftUI form of `KeepTheme.codeFont`: monospaced, and scaled with Dynamic Type like footnote text.
    private struct KeepCodeFont: ViewModifier {
        @ScaledMetric(relativeTo: .footnote) private var scale: CGFloat = 1
        let size: CGFloat
        let weight: Font.Weight

        func body(content: Content) -> some View {
            content.font(.system(size: size * scale, weight: weight, design: .monospaced))
        }
    }

    extension View {
        func keepCodeFont(size: CGFloat = 12, weight: Font.Weight = .regular) -> some View {
            modifier(KeepCodeFont(size: size, weight: weight))
        }
    }

    enum ByteCountDisplay {
        static func string(_ byteCount: Int) -> String {
            let count = max(0, byteCount)
            guard count >= 1000 else { return "\(count) B" }
            let kilobytes = Double(count) / 1024
            if kilobytes < 1000 {
                return String(format: "%.1f KB", kilobytes)
            }
            return String(format: "%.1f MB", kilobytes / 1024)
        }
    }

    #if KEEP_RUNESTONE
        final class KeepCodeTheme: Runestone.Theme {
            let font: UIFont
            let textColor = UIColor.label
            let gutterBackgroundColor = UIColor.secondarySystemBackground
            let gutterHairlineColor = UIColor.separator
            let lineNumberColor = UIColor.tertiaryLabel
            let lineNumberFont: UIFont
            let selectedLineBackgroundColor = UIColor.secondarySystemBackground
            let selectedLinesLineNumberColor = UIColor.label
            let selectedLinesGutterBackgroundColor = UIColor.secondarySystemBackground
            let invisibleCharactersColor = UIColor.tertiaryLabel
            let pageGuideHairlineColor = UIColor.separator
            let pageGuideBackgroundColor = UIColor.clear
            let markedTextBackgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            let selectionColor = UIColor.systemBlue.withAlphaComponent(0.25)

            init() {
                font = KeepTheme.codeFont()
                lineNumberFont = KeepTheme.codeFont()
            }

            func textColor(for highlightName: String) -> UIColor? {
                switch highlightName {
                case "property": return .systemPurple
                case "string": return .systemGreen
                case "number": return .systemOrange
                case "constant.builtin", "constant": return .systemPink
                case "punctuation": return .tertiaryLabel
                default: return nil
                }
            }
        }
    #endif
#endif
