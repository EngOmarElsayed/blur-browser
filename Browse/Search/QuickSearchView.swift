import SwiftUI

struct QuickSearchView: View {
    @FocusState private var textFiledFocus: Bool
    private let quickSearchHeight: CGFloat = 300
    let viewModel: QuickSearchViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))

                TextField("Search tabs, history, bookmarks...", text: Bindable(viewModel).searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                    .focused($textFiledFocus)
                    .onSubmit {
                        viewModel.selectResult()
                        onDismiss()
                    }
                    .onChange(of: viewModel.searchText) {
                        viewModel.updateResults()
                    }

                kbdBadge("⌘K")
            }
            .padding(.horizontal, 16)
            .frame(height: Layout.quickSearchInputHeight)

            Divider()

            // Results or empty state
            if viewModel.results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: Layout.quickSearchWidth, height: quickSearchHeight)
        .background(Color(nsColor: Colors.surfacePrimary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .onAppear { textFiledFocus = true }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color(nsColor: Colors.borderLight))
            Text(viewModel.searchText.isEmpty ? "Start typing to search" : "No results found")
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            Text(viewModel.searchText.isEmpty
                 ? "Search tabs, history, and the web"
                 : "Try a different search term")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    let grouped = Dictionary(grouping: viewModel.results, by: { $0.type })

                    ForEach([QuickSearchResultType.openTab, .history, .suggestion], id: \.self) { type in
                        if let items = grouped[type], !items.isEmpty {
                            sectionHeader(type.rawValue)
                            ForEach(items) { result in
                                resultRow(result, isSelected: result.id == viewModel.selectedID)
                                    .id(result.id)
                                    .onTapGesture {
                                        viewModel.selectedID = result.id
                                        viewModel.selectResult()
                                        onDismiss()
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedID) { _, newID in
                guard let newID else { return }
                withAnimation {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultRow(_ result: QuickSearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
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

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
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
