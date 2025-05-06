//
//  FilterView.swift
//  Keep
//
//  Created by Michael Amiro on 24/04/2025.
//

import SwiftUI
import Logging

@available(iOS 13.0, *)
struct FilterView: View {
    let levels = Logger.Level.allCases
    @Binding var selectedLevel: Logger.Level?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button {
                    withAnimation {
                        selectedLevel = nil
                    }
                } label: {
                    Text("All")
                        .font(.system(size: 13))
                        .fontWeight(.semibold)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .foregroundColor(selectedLevel == nil ? .accentColor : Color.primary.opacity(0.8))
                        .background(selectedLevel == nil ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.4))
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .id(0)
                ForEach(levels, id: \.rawValue) { level in
                    Button {
                        withAnimation {
                            selectedLevel = level
                        }
                    } label: {
                        Text(level.rawValue.capitalized)
                            .font(.system(size: 13))
                            .fontWeight(.semibold)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .foregroundColor(selectedLevel == level ? level.color : Color.primary.opacity(0.8))
                            .background(level == selectedLevel ? level.color.opacity(0.2) : Color.gray.opacity(0.4))
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .id(level.hashValue)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var selectedLevel: Logger.Level? = .debug
    FilterView(selectedLevel: $selectedLevel)
}
