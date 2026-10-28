#if canImport(UIKit)
    import UIKit

    struct KeepKeyValue: Sendable {
        let key: String
        let value: String

        init(_ key: String, _ value: String) {
            self.key = key
            self.value = value
        }
    }

    final class KeyValueListView: UIView {
        private let rowsStack = UIStackView()

        init(rows: [KeepKeyValue]) {
            super.init(frame: .zero)
            layer.borderColor = UIColor.separator.cgColor
            layer.borderWidth = 0.5
            layer.cornerRadius = 9
            clipsToBounds = true

            rowsStack.axis = .vertical
            rowsStack.spacing = 0
            rowsStack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rowsStack)
            NSLayoutConstraint.activate([
                rowsStack.topAnchor.constraint(equalTo: topAnchor),
                rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
                rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
                rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            for (index, row) in rows.enumerated() {
                if index > 0 {
                    let separator = UIView()
                    separator.backgroundColor = .separator
                    separator.translatesAutoresizingMaskIntoConstraints = false
                    rowsStack.addArrangedSubview(separator)
                    separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                }
                rowsStack.addArrangedSubview(makeRow(row))
            }
            isHidden = rows.isEmpty
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        private func makeRow(_ row: KeepKeyValue) -> UIView {
            let container = UIView()
            container.backgroundColor = .secondarySystemBackground

            let keyLabel = UILabel()
            keyLabel.text = row.key
            keyLabel.textColor = .secondaryLabel
            keyLabel.font = .preferredFont(forTextStyle: .caption1)
            keyLabel.adjustsFontForContentSizeCategory = true
            keyLabel.numberOfLines = 0

            let valueLabel = CopyValueLabel(value: row.value)
            valueLabel.text = row.value
            valueLabel.font = KeepTheme.codeFont(ofSize: 12)
            valueLabel.adjustsFontForContentSizeCategory = true
            valueLabel.textColor = .label
            valueLabel.numberOfLines = 0
            valueLabel.lineBreakMode = .byCharWrapping

            let stack = UIStackView(arrangedSubviews: [keyLabel, valueLabel])
            stack.axis = .horizontal
            stack.alignment = .top
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9),
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -11),
                keyLabel.widthAnchor.constraint(equalToConstant: 86)
            ])
            return container
        }
    }

    private final class CopyValueLabel: UILabel, UIContextMenuInteractionDelegate {
        private let copiedValue: String

        init(value: String) {
            copiedValue = value
            super.init(frame: .zero)
            addInteraction(UIContextMenuInteraction(delegate: self))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: [
                    UIAction(title: "Copy Value", image: UIImage(systemName: "doc.on.doc")) { _ in
                        copyToPasteboard(self.copiedValue) {}
                    }
                ])
            }
        }
    }
#endif
