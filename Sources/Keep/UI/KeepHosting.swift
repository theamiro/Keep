#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Asks the enclosing `KeepHostingView` to measure its SwiftUI content again. Call it when a view's own state
    /// changes its height, such as expanding a disclosure.
    struct KeepInvalidateSize: Sendable {
        fileprivate let action: @MainActor @Sendable () -> Void

        @MainActor func callAsFunction() {
            action()
        }
    }

    private struct KeepInvalidateSizeKey: EnvironmentKey {
        static let defaultValue = KeepInvalidateSize {}
    }

    extension EnvironmentValues {
        var keepInvalidateSize: KeepInvalidateSize {
            get { self[KeepInvalidateSizeKey.self] }
            set { self[KeepInvalidateSizeKey.self] = newValue }
        }
    }

    /// The root of every hosted view. Ignores the safe area so content does not shift as it scrolls under bars.
    private struct HostedRoot<Content: View>: View {
        let content: Content
        let invalidateSize: KeepInvalidateSize

        var body: some View {
            content
                .environment(\.keepInvalidateSize, invalidateSize)
                .ignoresSafeArea()
        }
    }

    /// Shows a SwiftUI view inside UIKit layout, such as a detail screen's stack or a table's background view.
    /// The height is measured for the width the view is given, so wrapping text sizes the same way on every OS.
    final class KeepHostingView<Content: View>: UIView {
        private let host: UIHostingController<HostedRoot<Content>>
        private var measuredWidth: CGFloat = 0

        init(_ content: Content) {
            host = UIHostingController(rootView: HostedRoot(content: content, invalidateSize: KeepInvalidateSize {}))
            super.init(frame: .zero)
            host.view.backgroundColor = .clear
            if #available(iOS 16.4, *) {
                host.safeAreaRegions = []
            }
            addSubview(host.view)
            update(content)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func update(_ content: Content) {
            host.rootView = HostedRoot(
                content: content,
                invalidateSize: KeepInvalidateSize { [weak self] in
                    self?.invalidateIntrinsicContentSize()
                })
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            let width = bounds.width > 0 ? bounds.width : UIView.layoutFittingExpandedSize.width
            let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            host.view.frame = bounds
            if bounds.width != measuredWidth {
                measuredWidth = bounds.width
                invalidateIntrinsicContentSize()
            }
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
                invalidateIntrinsicContentSize()
            }
        }
    }

    /// A table view cell that shows a SwiftUI row, so rows are SwiftUI while the list stays a `UITableView`.
    final class KeepHostingCell<Content: View>: UITableViewCell {
        static var reuseIdentifier: String {
            "KeepHostingCell.\(Content.self)"
        }

        /// Hosts the row before iOS 16, where `UIHostingConfiguration` is not available. Remove with the iOS 15 floor.
        private var legacyHost: UIHostingController<HostedRoot<Content>>?

        func setContent(_ content: Content) {
            if #available(iOS 16, *) {
                contentConfiguration = UIHostingConfiguration { content }.margins(.all, 0)
            } else {
                setLegacyContent(content)
            }
        }

        override func systemLayoutSizeFitting(
            _ targetSize: CGSize,
            withHorizontalFittingPriority horizontalPriority: UILayoutPriority,
            verticalFittingPriority verticalPriority: UILayoutPriority
        ) -> CGSize {
            guard let legacyHost else {
                return super.systemLayoutSizeFitting(
                    targetSize,
                    withHorizontalFittingPriority: horizontalPriority,
                    verticalFittingPriority: verticalPriority
                )
            }
            // Lay out at the target width first so the content view's width accounts for the accessory.
            bounds.size.width = targetSize.width
            layoutIfNeeded()
            let fitting = CGSize(width: contentView.bounds.width, height: .greatestFiniteMagnitude)
            return CGSize(width: targetSize.width, height: ceil(legacyHost.sizeThatFits(in: fitting).height))
        }

        private func setLegacyContent(_ content: Content) {
            let root = HostedRoot(content: content, invalidateSize: KeepInvalidateSize {})
            if let legacyHost {
                legacyHost.rootView = root
                return
            }
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            host.view.frame = contentView.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(host.view)
            legacyHost = host
        }
    }
#endif
