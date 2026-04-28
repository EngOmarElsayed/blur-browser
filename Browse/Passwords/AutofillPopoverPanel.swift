import AppKit
import SwiftUI

@MainActor
final class AutofillPopoverPanel {
    private let panel: NSPanel
    private var hosting: NSHostingView<AutofillPopoverView>?
    private var credentials: [Credential] = []
    private var selectedIndex = 0 {
        didSet { rebuildHostingView() }
    }
    private var onSelect: ((Credential) -> Void)?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = true
        panel.contentView = NSView()
    }

    /// Show the popover positioned just below `fieldRect` (in screen coordinates).
    /// If the field is too low on screen, flip above it.
    func show(below fieldRect: CGRect, in window: NSWindow,
              credentials: [Credential],
              onSelect: @escaping (Credential) -> Void) {
        guard !credentials.isEmpty else { return }
        self.credentials = credentials
        self.selectedIndex = 0
        self.onSelect = onSelect
        rebuildHostingView()

        let preferredHeight = min(240, max(48, CGFloat(credentials.count) * 48))
        var origin = NSPoint(x: fieldRect.minX, y: fieldRect.minY - preferredHeight - 4)
        if let screen = window.screen {
            // If clipping bottom of screen, flip above field instead.
            if origin.y < screen.visibleFrame.minY {
                origin.y = fieldRect.maxY + 4
            }
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 280, height: preferredHeight)),
                       display: true)
        panel.orderFront(nil)
        installMonitors()
    }

    func hide() {
        panel.orderOut(nil)
        removeMonitors()
        credentials = []
        onSelect = nil
        hosting?.removeFromSuperview()
        hosting = nil
    }

    private func rebuildHostingView() {
        guard let wrapper = panel.contentView else { return }
        let view = AutofillPopoverView(
            credentials: credentials,
            selectedIndex: Binding(
                get: { [weak self] in self?.selectedIndex ?? 0 },
                set: { [weak self] in self?.setSelectedIndexInternal($0) }
            ),
            onSelect: { [weak self] cred in
                // Capture the callback BEFORE hide() — hide() sets self.onSelect = nil.
                let cb = self?.onSelect
                self?.hide()
                cb?(cred)
            }
        )
        if let existing = hosting {
            existing.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            host.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: wrapper.topAnchor),
                host.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ])
            hosting = host
        }
    }

    /// Used by the SwiftUI Binding's setter and the keyboard monitor.
    /// Avoids re-entering didSet's rebuild when the value is unchanged.
    private func setSelectedIndexInternal(_ value: Int) {
        guard selectedIndex != value else { return }
        selectedIndex = value
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.isVisible else { return ev }
            switch ev.keyCode {
            case 125: // down arrow
                if !self.credentials.isEmpty {
                    self.setSelectedIndexInternal(min(self.selectedIndex + 1, self.credentials.count - 1))
                }
                return nil
            case 126: // up arrow
                if !self.credentials.isEmpty {
                    self.setSelectedIndexInternal(max(self.selectedIndex - 1, 0))
                }
                return nil
            case 36, 76: // return / numpad enter
                if self.credentials.indices.contains(self.selectedIndex) {
                    let cred = self.credentials[self.selectedIndex]
                    // Capture the callback BEFORE hide() — hide() sets self.onSelect = nil.
                    let cb = self.onSelect
                    self.hide()
                    cb?(cred)
                }
                return nil
            case 53: // escape
                self.hide()
                return nil
            default:
                return ev
            }
        }
        // Click anywhere outside our panel hides it. Local monitor sees clicks
        // inside our app; clicks in other apps cause window deactivation which
        // already auto-hides the panel via `hidesOnDeactivate = true`.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            guard let self, self.isVisible else { return ev }
            if ev.window === self.panel { return ev } // click inside panel -> let it through
            self.hide()
            return ev
        }
    }

    private func removeMonitors() {
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let c = localClickMonitor { NSEvent.removeMonitor(c); localClickMonitor = nil }
    }
}
