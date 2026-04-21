//
//  SidebarView.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 21/04/2026.
//

import SwiftUI

enum SidebarMode: String, CaseIterable {
    case tabs
    case history
}

/// Architectural note: History is a separate right-side panel; Downloads
/// replaces the tab list in-place in the sidebar. We keep `SidebarMode` for
/// the history panel toggle and use a local `TabAreaMode` here for the
/// in-sidebar swap between tabs and downloads list.
enum TabAreaMode {
    case tabs
    case downloads
}

/// Shared, externally-observable state for the sidebar so AppKit code (keyboard
/// shortcuts, menu items) can change `tabAreaMode` and SwiftUI will re-render.
@Observable
@MainActor
final class SidebarState {
    var tabAreaMode: TabAreaMode = .tabs
}

struct SidebarView: View {
    let tabManager: TabManager
    let historyStore: HistoryStore
    let downloadStore: DownloadStore
    @Bindable var state: SidebarState
    var onToggleHistory: (() -> Void)?
    var onCancelDownload: (UUID) -> Void = { _ in }
    var onPauseDownload: (UUID) -> Void = { _ in }
    var onResumeDownload: (UUID) -> Void = { _ in }
    @State private var hoveredTabID: UUID?
    @State private var hoveredPinnedTabID: UUID?
    @State private var searchText = ""
    @State private var isPinDropTargeted = false
    @State private var isUnpinDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarContentView(
                hoveredTabID: $hoveredTabID,
                isPinDropTargeted: $isPinDropTargeted,
                isUnpinDropTargeted: $isUnpinDropTargeted,
                tabAreaMode: state.tabAreaMode,
                tabManager: tabManager,
                downloadStore: downloadStore,
                onCancelDownload: onCancelDownload,
                onPauseDownload: onPauseDownload,
                onResumeDownload: onResumeDownload
            )

            SidebarButtons(
                tabAreaMode: $state.tabAreaMode,
                downloadStore: downloadStore,
                onToggleHistory: onToggleHistory
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(Color(nsColor: .clear))
    }
}
