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
        GridItem(.adaptive(minimum: 35, maximum: 36), spacing: 4)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if tabManager.pinnedTabs.isEmpty {
                pinnedEmptyState
            } else {
                Text("Pinned")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                // Grid
                LazyVGrid(columns: pinnedGridColumns, spacing: 6) {
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
}
