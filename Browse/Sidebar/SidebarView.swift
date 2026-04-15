import SwiftUI

enum SidebarMode: String, CaseIterable {
    case tabs
    case history
}

struct SidebarView: View {
    let tabManager: TabManager
    let historyStore: HistoryStore
    var onToggleHistory: (() -> Void)?
    @State private var hoveredTabID: UUID?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search field (below traffic lights + sidebar toggle area)
            searchField
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .opacity(0.0)
                .disabled(true)

            Divider()

            tabListView
        }
        .background(Color(nsColor: .clear))
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))

            TextField("Search or enter URL...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .onSubmit {
                    let text = searchText.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        tabManager.navigate(to: text)
                        searchText = ""
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: Colors.surfacePrimary).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: Colors.borderLight).opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Tab List

    private var tabListView: some View {
        VStack(spacing: 0) {
            // Tab header
            HStack {
                Text("Tabs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                Spacer()
                Button {
                    tabManager.addNewTab(url: URL(string: SettingsStore.shared.homepageURL))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Tab list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTabID,
                            isHovered: hoveredTabID == tab.id,
                            onSelect: { tabManager.selectTab(tab) },
                            onClose: { tabManager.closeTab(tab) },
                            onDuplicate: { tabManager.duplicateTab(tab) },
                            onCloseOthers: { tabManager.closeOtherTabs(except: tab) }
                        )
                        .onHover { isHovered in
                            hoveredTabID = isHovered ? tab.id : nil
                        }
                    }
                    .onMove { source, destination in
                        tabManager.moveTab(from: source, to: destination)
                    }
                }
            }

            Spacer()

            // Bottom actions
            Divider()
            HStack(spacing: 12) {
                Button {
                    SettingsWindowController.shared.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .buttonStyle(.plain)

                Button {
                    onToggleHistory?()
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
