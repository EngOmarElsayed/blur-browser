import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 450),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Pin the window in place — the title-bar drag and the
        // background drag both have to be off. `isMovable = false`
        // alone leaves the title bar draggable.
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 800, height: 500))
        window.minSize = NSSize(width: 800, height: 450)
        window.maxSize = NSSize(width: 800, height: 450)

        // Hide the standard traffic light buttons — we draw our own
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 450)
        hostingView.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
        container.addSubview(hostingView)
        window.contentView = container

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showSettings() {
        centerOverActiveBrowserWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Position the settings window at the true center of the active browser
    /// window (or the main screen if there's no browser window open).
    /// `NSWindow.center()` is biased — it places the window at ~1/3 from the
    /// top of the screen by Apple HIG convention, which looks off-center.
    private func centerOverActiveBrowserWindow() {
        guard let window else { return }
        let windowSize = window.frame.size

        let parentFrame: NSRect = {
            if let browser = NSApp.windows.first(where: {
                $0.isVisible && $0.windowController is BrowserWindowController
            }) {
                return browser.frame
            }
            return NSScreen.main?.visibleFrame ?? .zero
        }()

        let x = parentFrame.midX - windowSize.width / 2
        let y = parentFrame.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
