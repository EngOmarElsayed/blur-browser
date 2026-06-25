//
//  QuickSearchView.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import SwiftUI

struct QuickSearchView: View {
    @FocusState private var textFiledFocus: Bool
    @Bindable private var viewModel: QuickSearchViewModel
    private let quickSearchHeight: CGFloat = 300
    let onDismiss: () -> Void

    init(viewModel: QuickSearchViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: Colors.accentPrimary))

                TextField("Search tabs, history, bookmarks...", text: Bindable(viewModel).searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                    .focused($textFiledFocus)
                    .onChange(of: viewModel.searchText) {
                        viewModel.updateResults()
                    }

                kbdBadge("⌘K")
            }
            .padding(.horizontal, 16)
            .frame(height: Layout.quickSearchInputHeight)

            Divider()

            if !viewModel.groupedResults.isEmpty {
                QuickSearchResultView(
                    selectedID: $viewModel.selectedID,
                    groupedResults: viewModel.groupedResults
                ) {
                    viewModel.selectResult()
                    onDismiss()
                }
            }
        }
        .frame(width: Layout.quickSearchWidth)
        .background(Color(nsColor: Colors.surfacePrimary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { textFiledFocus = true }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Components
    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(nsColor: Colors.accentPrimary))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(nsColor: Colors.surfaceSecondary))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: Colors.borderLight), lineWidth: 1)
            )
    }
}
