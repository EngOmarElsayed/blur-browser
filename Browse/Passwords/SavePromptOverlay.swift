import AppKit
import SwiftUI

/// Top-left overlay that displays a SavePromptView when the coordinator's
/// `pendingSaveCredential` is non-nil. The overlay is a transparent container
/// added as a subview of WebViewController.view; the actual prompt is a
/// smaller pinned subview of the overlay.
final class SavePromptOverlay: NSView {
    private var pinnedWrapper: NSView?

    func show(view: SavePromptView, mode: SavePromptView.Mode) {
        hide()
        let host = NSHostingView(rootView: view)
        let height: CGFloat = (mode == .update) ? 210 : 180
        host.frame = NSRect(x: 0, y: 0, width: 360, height: height)
        let wrapper = NSView(frame: host.frame) // CLAUDE.md: never set NSHostingView as self.view directly
        host.autoresizingMask = [.width, .height]
        wrapper.addSubview(host)

        let containerBounds = bounds
        wrapper.frame = NSRect(
            x: 12,
            y: containerBounds.height - height - 12,
            width: 360,
            height: height
        )
        wrapper.autoresizingMask = [.minYMargin]
        wrapper.alphaValue = 0
        addSubview(wrapper)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            wrapper.animator().alphaValue = 1
        }
        pinnedWrapper = wrapper
    }

    func hide() {
        guard let wrapper = pinnedWrapper else { return }
        pinnedWrapper = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            wrapper.animator().alphaValue = 0
        } completionHandler: {
            wrapper.removeFromSuperview()
        }
    }

    /// Don't intercept clicks unless they hit the pinned wrapper.
    /// Mouse events outside the prompt fall through to the web view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let wrapper = pinnedWrapper else { return nil }
        let hit = super.hitTest(point)
        return wrapper.hitTest(point) != nil ? hit : nil
    }
}
