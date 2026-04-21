import AppKit

final class BrowserWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        minSize = NSSize(width: Layout.windowMinWidth, height: Layout.windowMinHeight)
        isReleasedWhenClosed = false
        backgroundColor = Colors.chromeBg

        // Allow fullscreen for both window and element (video) fullscreen
        collectionBehavior = [.fullScreenPrimary]

        // Explicitly set appearance so macOS renders traffic lights with correct colors
        appearance = NSAppearance(named: .aqua)

        // Attach a minimal toolbar so the titlebar region has proper height
        let toolbar = NSToolbar(identifier: "BrowserToolbar")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        toolbarStyle = .unified

        center()

        NotificationCenter.default.addObserver(
            self, selector: #selector(willEnterFullScreen),
            name: NSWindow.willEnterFullScreenNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(willExitFullScreen),
            name: NSWindow.willExitFullScreenNotification, object: self
        )
    }

    /// Re-apply theme-dependent colors (called by BrowserWindowController on theme change).
    func applyActiveTheme() {
        backgroundColor = Colors.chromeBg
    }

    @objc private func willEnterFullScreen() {
        toolbar?.isVisible = false
    }

    @objc private func willExitFullScreen() {
        toolbar?.isVisible = true
    }

    // Required for traffic lights to render in their active (colored) state
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Silently swallow key events that bubble up to the window unhandled.
    // WKWebView processes keys like arrow keys for in-page scrolling/video
    // seeking, but returns without marking the event as consumed — which causes
    // NSResponder's default behavior to beep. Overriding here prevents the beep
    // while still letting menu shortcuts work (they go through performKeyEquivalent).
    override func keyDown(with event: NSEvent) {
        // no-op — do NOT call super which triggers NSBeep via noResponder(for:)
    }
}
