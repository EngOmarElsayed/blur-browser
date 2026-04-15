import AppKit
import SwiftUI

/// Hosts the Quick Search overlay as an NSHostingView inside a parent NSView (the web content area).
@MainActor
final class QuickSearchOverlay {
    private var hostingView: NSHostingView<QuickSearchView>?
    private var dimmingView: BlockingDimView?
    private let viewModel: QuickSearchViewModel
    private var keyMonitor: Any?

    var isVisible: Bool { hostingView != nil }

    init(tabManager: TabManager, historyStore: HistoryStore) {
        self.viewModel = QuickSearchViewModel(tabManager: tabManager, historyStore: historyStore)
    }

    func show(in parent: NSView, navigateInNewTab: Bool = false) {
        guard hostingView == nil else { return }

        viewModel.searchText = ""
        viewModel.navigateInNewTab = navigateInNewTab
        viewModel.updateResults()

        // Dimming backdrop — blocks all interaction with views underneath
        let dimming = BlockingDimView(frame: parent.bounds)
        dimming.onClickOutside = { [weak self] in
            self?.dismiss()
        }
        dimming.autoresizingMask = [.width, .height]
        parent.addSubview(dimming)
        self.dimmingView = dimming

        // Quick search SwiftUI view
        let searchView = QuickSearchView(viewModel: viewModel) { [weak self] in
            self?.dismiss()
        }
        let hosting = NSHostingView(rootView: searchView)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        hosting.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
        hosting.layer?.shadowOffset = CGSize(width: 0, height: -4)
        hosting.layer?.shadowRadius = 20
        hosting.layer?.shadowOpacity = 1

        parent.addSubview(hosting)
        self.hostingView = hosting

        layoutInParent(parent)

        // Key monitor for escape and arrow keys
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 { // Escape
                self.dismiss()
                return nil
            }
            if event.keyCode == 125 { // Down arrow
                self.viewModel.moveSelectionDown()
                return nil
            }
            if event.keyCode == 126 { // Up arrow
                self.viewModel.moveSelectionUp()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        hostingView?.removeFromSuperview()
        hostingView = nil
        dimmingView?.removeFromSuperview()
        dimmingView = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func toggle(in parent: NSView, navigateInNewTab: Bool = false) {
        if isVisible {
            dismiss()
        } else {
            show(in: parent, navigateInNewTab: navigateInNewTab)
        }
    }

    func layoutInParent(_ parent: NSView) {
        guard let hosting = hostingView else { return }
        let parentBounds = parent.bounds
        let width = Layout.quickSearchWidth
        let height: CGFloat = 300
        let x = (parentBounds.width - width) / 2
        let y = (parentBounds.height - height) / 2
        hosting.frame = NSRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Blocking Dim View

/// An NSView that intercepts ALL mouse events so nothing passes through to views underneath.
private final class BlockingDimView: NSView {
    var onClickOutside: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { onClickOutside?() }
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) { onClickOutside?() }
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) { onClickOutside?() }
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(convert(point, from: superview)) {
            return self
        }
        return nil
    }
}
