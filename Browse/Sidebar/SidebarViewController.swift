import AppKit
import SwiftUI

@MainActor
final class SidebarViewController: NSViewController {

    private let tabManager: TabManager
    private let historyStore: HistoryStore
    private var hostingController: NSHostingController<SidebarView>!

    /// Called when the user taps the history (clock) button in the sidebar
    var onToggleHistory: (() -> Void)?

    init(tabManager: TabManager, historyStore: HistoryStore) {
        self.tabManager = tabManager
        self.historyStore = historyStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // Use a plain container view — never set NSHostingView as self.view directly
        let container = NSView()
        container.wantsLayer = true
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarView = SidebarView(
            tabManager: tabManager,
            historyStore: historyStore,
            onToggleHistory: { [weak self] in
                self?.onToggleHistory?()
            }
        )
        hostingController = NSHostingController(rootView: sidebarView)
        // sizingOptions = [] prevents the hosting controller from imposing its own intrinsic size
        // which avoids fighting with the NSSplitView constraints
        hostingController.sizingOptions = []
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)

        // Use high (non-required) priority so constraints don't conflict with
        // the autoresizing-mask width=0 constraint during the initial layout pass.
        let constraints = [
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        constraints.forEach { $0.priority = .init(999) }
        NSLayoutConstraint.activate(constraints)
    }
}
