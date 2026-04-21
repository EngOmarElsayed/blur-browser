//
//  FaviconView.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 21/04/2026.
//

import SwiftUI

struct FaviconView: View {
    let faviconURL: URL?
    
    var body: some View {
        AsyncImage(cachingPolicy: .duringAppSession, from: faviconURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            default:
                globePlaceholder
            }
        }
    }
    
    // MARK: - Private view
    private var globePlaceholder: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: Colors.borderLight).opacity(0.5))
            .frame(width: 16, height: 16)
            .overlay(
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            )
    }
}
