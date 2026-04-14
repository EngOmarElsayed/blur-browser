import AppKit
import SwiftUI

@MainActor
final class MainSplitViewController: NSViewController {

    let tabManager: TabManager
    let historyStore: HistoryStore
    let webViewController: WebViewController
    let addressBar: AddressBarViewController

    private var sidebarVC: SidebarViewController!
    private var historyHostingVC: NSHostingController<HistoryPanelView>!
    private let leftDividerView = ResizeDividerView()
    private let rightDividerView = ResizeDividerView()

    private var sidebarWidth: CGFloat = Layout.sidebarDefaultWidth
    private var historyPanelWidth: CGFloat = 300
    private var isSidebarCollapsed = false
    private var isHistoryCollapsed = true
    private var toolbarView: NSView!
    private let sidebarToggleButton = NSButton()

    init(tabManager: TabManager, historyStore: HistoryStore) {
        self.tabManager = tabManager
        self.historyStore = historyStore
        self.webViewController = WebViewController(tabManager: tabManager)
        self.addressBar = AddressBarViewController(tabManager: tabManager)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // -- Left sidebar --
        sidebarVC = SidebarViewController(tabManager: tabManager, historyStore: historyStore)
        sidebarVC.onToggleHistory = { [weak self] in
            self?.toggleHistoryMode()
        }
        addChild(sidebarVC)
        view.addSubview(sidebarVC.view)

        // -- Sidebar toggle button --
        sidebarToggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
        sidebarToggleButton.isBordered = false
        sidebarToggleButton.bezelStyle = .accessoryBarAction
        sidebarToggleButton.contentTintColor = Colors.foregroundMuted
        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(sidebarToggleTapped)
        view.addSubview(sidebarToggleButton)

        // -- Toolbar --
        addressBar.onToggleSidebar = { [weak self] in
            self?.toggleSidebar()
        }
        toolbarView = makeToolbarView()
        view.addSubview(toolbarView)

        // -- Web content --
        addChild(webViewController)
        view.addSubview(webViewController.view)

        // -- Right history panel (created once, starts hidden) --
        let panelView = HistoryPanelView(
            historyStore: historyStore,
            tabManager: tabManager,
            onDismiss: { [weak self] in
                self?.toggleHistoryMode()
            }
        )
        historyHostingVC = NSHostingController(rootView: panelView)
        historyHostingVC.sizingOptions = []
        historyHostingVC.view.wantsLayer = true
        historyHostingVC.view.layer?.backgroundColor = Colors.sidebarBg.cgColor
        addChild(historyHostingVC)
        view.addSubview(historyHostingVC.view)
        historyHostingVC.view.isHidden = true

        // -- Dividers: added last so they're on top --
        view.addSubview(leftDividerView)
        let leftPan = NSPanGestureRecognizer(target: self, action: #selector(handleLeftDividerDrag(_:)))
        leftDividerView.addGestureRecognizer(leftPan)

        rightDividerView.isHidden = true
        view.addSubview(rightDividerView)
        let rightPan = NSPanGestureRecognizer(target: self, action: #selector(handleRightDividerDrag(_:)))
        rightDividerView.addGestureRecognizer(rightPan)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubviews()
    }

    private func layoutSubviews() {
        let bounds = view.bounds
        let toolbarHeight = Layout.toolbarHeight
        let dividerWidth: CGFloat = 1
        let dividerHitWidth: CGFloat = 16

        // ── Left sidebar ──
        let effectiveSidebarWidth = isSidebarCollapsed ? 0 : sidebarWidth

        sidebarVC.view.frame = NSRect(x: 0, y: 0, width: effectiveSidebarWidth, height: bounds.height)
        sidebarVC.view.isHidden = isSidebarCollapsed

        // Sidebar toggle button
        let toggleSize: CGFloat = 28
        let trafficLightCenterY: CGFloat
        if let closeButton = view.window?.standardWindowButton(.closeButton) {
            let closeFrame = closeButton.convert(closeButton.bounds, to: view)
            trafficLightCenterY = closeFrame.midY
        } else {
            trafficLightCenterY = bounds.height - 14
        }
        sidebarToggleButton.isHidden = isSidebarCollapsed
        if !isSidebarCollapsed {
            sidebarToggleButton.frame = NSRect(
                x: effectiveSidebarWidth - toggleSize - 8,
                y: trafficLightCenterY - toggleSize / 2,
                width: toggleSize, height: toggleSize
            )
        }

        // Left divider
        leftDividerView.frame = NSRect(
            x: effectiveSidebarWidth - (dividerHitWidth - dividerWidth) / 2,
            y: 0, width: dividerHitWidth, height: bounds.height
        )
        leftDividerView.isHidden = isSidebarCollapsed
        view.addSubview(leftDividerView, positioned: .above, relativeTo: nil)

        let contentX = effectiveSidebarWidth + (isSidebarCollapsed ? 0 : dividerWidth)

        // ── Right history panel ──
        let effectiveHistoryWidth = isHistoryCollapsed ? 0 : historyPanelWidth

        historyHostingVC.view.isHidden = isHistoryCollapsed
        historyHostingVC.view.frame = NSRect(
            x: bounds.width - effectiveHistoryWidth,
            y: 0,
            width: effectiveHistoryWidth,
            height: bounds.height
        )

        // Right divider
        rightDividerView.isHidden = isHistoryCollapsed
        if !isHistoryCollapsed {
            rightDividerView.frame = NSRect(
                x: bounds.width - effectiveHistoryWidth - (dividerHitWidth - dividerWidth) / 2,
                y: 0, width: dividerHitWidth, height: bounds.height
            )
            view.addSubview(rightDividerView, positioned: .above, relativeTo: nil)
        }

        // ── Content area (toolbar + web view) ──
        let contentRight = isHistoryCollapsed ? 0 : effectiveHistoryWidth + dividerWidth
        let fullContentWidth = bounds.width - contentX - contentRight

        toolbarView.frame = NSRect(
            x: contentX,
            y: bounds.height - toolbarHeight,
            width: fullContentWidth,
            height: toolbarHeight
        )

        let webHeight = bounds.height - toolbarHeight
        webViewController.view.frame = NSRect(
            x: contentX, y: 0,
            width: fullContentWidth,
            height: webHeight
        )
    }

    private func makeToolbarView() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Colors.surfaceSecondary.cgColor

        addChild(addressBar)
        addressBar.view.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(addressBar.view)

        NSLayoutConstraint.activate([
            addressBar.view.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            addressBar.view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            addressBar.view.topAnchor.constraint(equalTo: bar.topAnchor),
            addressBar.view.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        return bar
    }

    // MARK: - Actions

    @objc private func sidebarToggleTapped() {
        toggleSidebar()
    }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isSidebarCollapsed.toggle()
            addressBar.setSidebarCollapsed(isSidebarCollapsed)
            layoutSubviews()
        }
    }

    func toggleHistoryMode() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isHistoryCollapsed.toggle()
            layoutSubviews()
        }
    }

    // MARK: - Divider Drag

    @objc private func handleLeftDividerDrag(_ gesture: NSPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let newWidth = max(Layout.sidebarMinWidth, min(Layout.sidebarMaxWidth, location.x))
        sidebarWidth = newWidth
        layoutSubviews()
    }

    @objc private func handleRightDividerDrag(_ gesture: NSPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let newWidth = max(Layout.sidebarMinWidth, min(Layout.sidebarMaxWidth, view.bounds.width - location.x))
        historyPanelWidth = newWidth
        layoutSubviews()
    }
}

// MARK: - Resize Divider View

final class ResizeDividerView: NSView {

    private let lineLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        lineLayer.backgroundColor = Colors.borderLight.cgColor
        layer?.addSublayer(lineLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let lineX = (bounds.width - 1) / 2
        lineLayer.frame = CGRect(x: lineX, y: 0, width: 1, height: bounds.height)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}
