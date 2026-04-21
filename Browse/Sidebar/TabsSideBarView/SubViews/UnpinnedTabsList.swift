//
//  UnpinnedTabsList.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 21/04/2026.
//

import SwiftUI

struct UnpinnedTabsList: View {
    @Binding var hoveredTabID: UUID?
    @Binding var isPinDropTargeted: Bool
    @Binding var isUnpinDropTargeted: Bool
    let tabManager: TabManager

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Tabs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                Spacer()
                Button {
                    tabManager.addNewTab(url: nil)
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
        }
    }
}
