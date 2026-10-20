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
        HStack(spacing: 2) {
            FooterButton(symbol: "square.stack", help: "Tabs", isActive: tabAreaMode == .tabs) {
                tabAreaMode = .tabs
            }

            FooterButton(symbol: "arrow.down.circle", help: "Downloads", isActive: tabAreaMode == .downloads) {
                tabAreaMode = .downloads
            }
            .overlay(alignment: .topTrailing) {
                if activeDownloadCount > 0 {
                    DownloadsBadge(count: activeDownloadCount)
                        .offset(x: -2, y: 2)
                        .allowsHitTesting(false)
                }
            }

            FooterButton(symbol: "clock.arrow.circlepath", help: "History") {
                onToggleHistory?()
            }

            ThemePaletteAnchorButton()
                .frame(width: 30, height: 30)
                .help("Change Theme")
                .accessibilityLabel("Change theme")

            FooterButton(symbol: "gearshape", help: "Settings") {
                SettingsWindowController.shared.showSettings()
            }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Footer Button

private struct FooterButton: View {
    let symbol: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(nsColor: isActive ? Colors.accentPrimary : Colors.foregroundSecondary))
                .frame(width: 30, height: 30)
                .background {
                    if isActive || isHovered {
                        Circle().fill(
                            isActive
                                ? Color(nsColor: Colors.accentPrimary).opacity(0.16)
                                : Color(nsColor: Colors.foregroundPrimary).opacity(0.08)
                        )
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.15), value: isHovered)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Theme Palette Anchor

/// SwiftUI wrapper around an NSView that anchors the theme picker NSPopover.
/// Needed because NSPopover.show(relativeTo:of:preferredEdge:) needs an AppKit
/// view to attach to, and the surrounding sidebar is pure SwiftUI.
private struct ThemePaletteAnchorButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Change theme")
        button.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        button.contentTintColor = Colors.foregroundSecondary
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped(_:))
        // Compact size to match other sidebar footer icons
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.contentTintColor = Colors.foregroundSecondary
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        @MainActor
        @objc func tapped(_ sender: NSButton) {
            ThemePickerPopoverController.shared.show(relativeTo: sender)
        }
    }
}

// MARK: - Badge

private struct DownloadsBadge: View {
    let count: Int

    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 8, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(minWidth: 13, minHeight: 13)
            .padding(.horizontal, 2)
            .background(Capsule().fill(Color(nsColor: Colors.accentPrimary)))
    }
}
