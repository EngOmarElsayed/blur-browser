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
    @State private var hoveredPinnedTabID: UUID?
    @State private var searchText = ""
    @State private var isPinDropTargeted = false
    @State private var isUnpinDropTargeted = false

    private let pinnedGridColumns = [
        GridItem(.adaptive(minimum: 35, maximum: 36), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Pinned section — always visible
            pinnedSection
                .padding(.top, 8)

            tabListView
                .padding(.top, 4)
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

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        VStack(spacing: 0) {
            // Header
            if !tabManager.pinnedTabs.isEmpty {
                Text("Pinned")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if tabManager.pinnedTabs.isEmpty {
                pinnedEmptyState
            } else {
                // Grid
                LazyVGrid(columns: pinnedGridColumns, spacing: 6) {
                    ForEach(tabManager.pinnedTabs) { tab in
                        PinnedTabItemView(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTabID,
                            isHovered: hoveredPinnedTabID == tab.id,
                            onSelect: { tabManager.selectTab(tab) },
                            onUnpin: { tabManager.unpinTab(tab) },
                            onDuplicate: { tabManager.duplicateTab(tab) }
                        )
                        .onHover { isHovered in
                            hoveredPinnedTabID = isHovered ? tab.id : nil
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            // Divider
            Divider()
                .padding(.horizontal, 8)
                .padding(.top, 12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: Colors.accentPrimary).opacity(isPinDropTargeted ? 0.6 : 0), lineWidth: 2)
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.15), value: isPinDropTargeted)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let tabID = UUID(uuidString: idString),
                  let tab = tabManager.tabs.first(where: { $0.id == tabID }),
                  !tab.isPinned
            else { return false }
            tabManager.pinTab(tab)
            return true
        } isTargeted: { targeted in
            isPinDropTargeted = targeted
        }
    }

    // MARK: - Pinned Empty State

    private var pinnedEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "pin")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.5))
                .rotationEffect(.degrees(45))

            Text("Right-click a tab to pin it")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color(nsColor: Colors.borderLight))
        )
        .padding(.horizontal, 10)
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

            // Tab list (unpinned only)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(tabManager.unpinnedTabs) { tab in
                        TabItemView(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTabID,
                            isHovered: hoveredTabID == tab.id,
                            onSelect: { tabManager.selectTab(tab) },
                            onClose: { tabManager.closeTab(tab) },
                            onPin: { tabManager.pinTab(tab) },
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
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: Colors.accentPrimary).opacity(isUnpinDropTargeted ? 0.6 : 0), lineWidth: 2)
                    .padding(.horizontal, 4)
                    .animation(.easeInOut(duration: 0.15), value: isUnpinDropTargeted)
            )
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let tabID = UUID(uuidString: idString),
                      let tab = tabManager.tabs.first(where: { $0.id == tabID }),
                      tab.isPinned
                else { return false }
                tabManager.unpinTab(tab)
                return true
            } isTargeted: { targeted in
                isUnpinDropTargeted = targeted
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
