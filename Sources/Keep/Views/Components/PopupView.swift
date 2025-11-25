//
//  PopupView.swift
//  Keep
//
//  Created by Michael Amiro on 25/11/2025.
//

import SwiftUI

struct PopupView: View {
    let message: String
    var body: some View {
        if #available(iOS 15.0, *) {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(24.0)
                .padding(.horizontal)
        } else {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.8))
                .cornerRadius(24.0)
                .padding(.horizontal)
        }
    }
}

#Preview {
    PopupView(message: "Copied!")
    PopupView(message: "All logs have been cleared!")
}
