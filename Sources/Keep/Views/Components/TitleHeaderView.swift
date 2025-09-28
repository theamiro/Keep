//
//  TitleHeaderView.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

#if canImport(UIKit)
import SwiftUI

struct TitleHeaderView: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 16))
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
@available(iOS 17.0, *)
#Preview {
    TitleHeaderView(title: "Metadata")
        .padding(.horizontal)
}
#endif
