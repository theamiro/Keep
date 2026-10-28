#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// The log viewer for SwiftUI. Use `.keepViewer(isPresented:)` to show it as a sheet.
    public struct KeepView: UIViewControllerRepresentable {
        public init() {}

        public func makeUIViewController(context _: Context) -> UIViewController {
            Keep.makeViewer()
        }

        public func updateUIViewController(_: UIViewController, context _: Context) {}
    }

    extension View {
        /// Shows the Keep log viewer as a sheet while `isPresented` is true.
        public func keepViewer(isPresented: Binding<Bool>) -> some View {
            sheet(isPresented: isPresented) {
                KeepView()
            }
        }
    }
#endif
