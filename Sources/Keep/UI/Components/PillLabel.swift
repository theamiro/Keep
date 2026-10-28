#if canImport(UIKit)
    import UIKit

    final class PillLabel: UILabel {
        private let insets = UIEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)

        init(text: String, color: UIColor, background: UIColor) {
            super.init(frame: .zero)
            self.text = text
            textColor = color
            backgroundColor = background
            font = KeepTheme.codeFont(ofSize: 11, weight: .semibold)
            adjustsFontForContentSizeCategory = true
            textAlignment = .center
            numberOfLines = 1
            layer.cornerRadius = 5
            layer.masksToBounds = true
            setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: insets))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(
                width: size.width + insets.left + insets.right,
                height: size.height + insets.top + insets.bottom
            )
        }
    }
#endif
