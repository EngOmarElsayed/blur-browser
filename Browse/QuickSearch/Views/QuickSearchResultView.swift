//
//  QuickSearchResultView.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import SwiftUI

struct QuickSearchResultView: View {
    @Binding var selectedID: UUID?
    let groupedResults: [QuickSearchResultType : [QuickSearchResult]]
    let selecteAction: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(QuickSearchResultType.allCases, id: \.self) { type in
                        if let items = groupedResults[type] {
                            VStack(spacing: 0) {
                                QuickSearchSectionHeader(title: type.rawValue)

                                ForEach(items) { result in
                                    QuickSearchRowResultView(result: result, isSelected: result.id == selectedID)
                                        .id(result.id)
                                        .onTapGesture {
                                            selectedID = result.id
                                            selecteAction()
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedID) { _, newID in
                guard let newID else { return }
                withAnimation { proxy.scrollTo(newID, anchor: .center) }
            }
        }
    }

    // MARK: - SubViews
    private struct QuickSearchSectionHeader: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.accentPrimary).opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct QuickSearchRowResultView: View {
        let result: QuickSearchResult
        let isSelected: Bool

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: result.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                        .lineLimit(1)
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: Colors.accentPrimary).opacity(0.8))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: Layout.quickSearchResultHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(nsColor: Colors.hoverBg) : Color.clear)
            )
            .padding(.horizontal, 4)
        }
    }
}
