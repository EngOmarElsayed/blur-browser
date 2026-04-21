//
//  SidebarContentView.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 21/04/2026.
//

import SwiftUI

struct SidebarContentView: View {
    @Binding var hoveredTabID: UUID?
    @Binding var isPinDropTargeted: Bool
    @Binding var isUnpinDropTargeted: Bool

    let tabAreaMode: TabAreaMode
    let tabManager: TabManager
    let downloadStore: DownloadStore
    let onCancelDownload: (UUID) -> Void
    let onPauseDownload: (UUID) -> Void
    let onResumeDownload: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch tabAreaMode {
            case .tabs:
                // Pinned section — always visible
                PinnedTabsGrid(
                    isPinDropTargeted: $isPinDropTargeted,
                    tabManager: tabManager
                )
                    .padding(.top, 8)

                UnpinnedTabsList(
                    hoveredTabID: $hoveredTabID,
                    isPinDropTargeted: $isPinDropTargeted,
                    isUnpinDropTargeted: $isUnpinDropTargeted,
                    tabManager: tabManager
                )
                    .padding(.top, 4)

            case .downloads:
                DownloadsPanelView(
                    store: downloadStore,
                    onCancel: onCancelDownload,
                    onPause: onPauseDownload,
                    onResume: onResumeDownload
                )
                    .padding(.top, 4)
            }
        }
    }
}
