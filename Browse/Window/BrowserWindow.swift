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
        backgroundColor = Colors.surfaceSecondary

        // Explicitly set appearance so macOS renders traffic lights with correct colors
        appearance = NSAppearance(named: .aqua)

        // Attach a minimal toolbar so the titlebar region has proper height
        let toolbar = NSToolbar(identifier: "BrowserToolbar")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        toolbarStyle = .unified

        center()
    }

    // Required for traffic lights to render in their active (colored) state
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
