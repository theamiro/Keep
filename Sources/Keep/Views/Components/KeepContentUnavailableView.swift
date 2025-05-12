//
//  KeepContentUnavailableView.swift
//  Keep
//
//  Created by Michael Amiro on 12/05/2025.
//

import UIKit
import SwiftUI

@available(iOS 13.0, *)
struct ContentUnavailableModel {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
}

@available(iOS 13.0, *)
struct KeepContentUnavailableView: View {
    let model: ContentUnavailableModel
    var body: some View {
        VStack {
            if #available(iOS 17.0, *) {
                ContentUnavailableView {
                    Label(model.title, systemImage: model.systemImage)
                } description: {
                    Text(model.description)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: model.systemImage)
                        .resizable()
                        .frame(width: 54, height: 40)
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.secondary)
                    VStack(spacing: 4) {
                        Text(model.title)
                            .font(.system(size: 21))
                            .fontWeight(.bold)
                        Text(model.description)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }
}

@available(iOS 13.0, *)
#Preview {
    KeepContentUnavailableView(model: ContentUnavailableModel(title: "No logs available yet", systemImage: "tray.fill", description: "Continue using the application\nto view logs later."))
}

@available(iOS 13.0, *)
final class ContentUnavailableCell: UITableViewCell {
    private var hostController: UIHostingController<KeepContentUnavailableView>?
    func configure(with model: ContentUnavailableModel, parent: UIViewController) {
      let view = KeepContentUnavailableView(model: model)
      if let hostController = hostController {
        hostController.rootView = view
        hostController.view.invalidateIntrinsicContentSize()
      } else {
        let controller = UIHostingController(rootView: view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear

        parent.addChild(controller)
        contentView.addSubview(controller.view)
        controller.didMove(toParent: parent)

        NSLayoutConstraint.activate([
          controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
          controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
          controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
          controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        hostController = controller
      }
    }
}
