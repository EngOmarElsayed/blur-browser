//
//  SidebarButtons.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 21/04/2026.
//

import SwiftUI

struct SidebarButtons: View {
    @Binding var tabAreaMode: TabAreaMode
    let downloadStore: DownloadStore
    var onToggleHistory: (() -> Void)?

    /// How many downloads are still running — drives the badge count.
    private var activeDownloadCount: Int {
        downloadStore.items.filter { $0.status == .inProgress }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                tabAreaMode = .tabs
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .opacity(tabAreaMode == .tabs ? 0.8 : 1)
            }
            .buttonStyle(.plain)
            .disabled(tabAreaMode == .tabs)
            .help("Back to Tabs")

            Button {
                tabAreaMode = .downloads
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .opacity(tabAreaMode == .downloads ? 0.8 : 1)
                    .overlay(alignment: .topTrailing) {
                        if activeDownloadCount > 0 {
                            DownloadsBadge(count: activeDownloadCount)
                                .offset(x: 8, y: -5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(tabAreaMode == .downloads)
            .help("Downloads")

            Button {
                onToggleHistory?()
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            }
            .buttonStyle(.plain)

            Button {
                SettingsWindowController.shared.showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Badge

private struct DownloadsBadge: View {
    let count: Int

    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 12, minHeight: 12)
            .padding(.horizontal, 3)
            .background(
                Circle().fill(Color(nsColor: Colors.accentPrimary))
            )
            .overlay(
                Circle()
                    .stroke(Color(nsColor: Colors.surfacePrimary), lineWidth: 1.5)
            )
    }
}
