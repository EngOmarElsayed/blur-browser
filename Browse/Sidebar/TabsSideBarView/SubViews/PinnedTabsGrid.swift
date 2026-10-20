//
//  PinnedTabsGrid.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 21/04/2026.
//

import SwiftUI

struct PinnedTabsGrid: View {
    @Binding var isPinDropTargeted: Bool
    @State private var hoveredPinnedTabID: UUID?

    let tabManager: TabManager

    private let pinnedGridColumns = [
        GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if tabManager.pinnedTabs.isEmpty {
                pinnedEmptyState
            } else {
                SidebarSectionHeader(title: "Pinned")
                    .padding(.bottom, 8)

                // Grid — one glass container so neighboring tiles blend as they move
                GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: pinnedGridColumns, spacing: 8) {
                    ForEach(tabManager.pinnedTabs) { tab in
                        PinnedTabItemView(
                            tab: tab,
                            isSelected: tab.id == tabManager.selectedTab?.id,
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
                }
                .padding(.horizontal, 12)
            }

            Divider()
                .padding(.horizontal, 14)
                .padding(.top, 14)
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
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                .rotationEffect(.degrees(45))

            Text("Drag a tab here to pin it")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted).opacity(0.5))
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Section Header

/// Small, legible section label used across the sidebar ("Pinned", "Tabs").
struct SidebarSectionHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
            Spacer()
            accessory
        }
        .padding(.horizontal, 16)
    }
}

extension SidebarSectionHeader where Accessory == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
