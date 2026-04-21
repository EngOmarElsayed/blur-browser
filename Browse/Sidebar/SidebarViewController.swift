import AppKit
import SwiftUI

@MainActor
final class SidebarViewController: NSViewController {

    private let tabManager: TabManager
    private let historyStore: HistoryStore
    private let downloadStore: DownloadStore
    private let sidebarState = SidebarState()
    private var hostingController: NSHostingController<SidebarView>!

    /// Programmatically switch the sidebar to its Downloads list.
    func showDownloads() {
        sidebarState.tabAreaMode = .downloads
    }

    /// Programmatically switch the sidebar back to the Tabs list.
    func showTabs() {
        sidebarState.tabAreaMode = .tabs
    }

    /// Toggle between the Downloads list and the Tabs list.
    func toggleDownloads() {
        sidebarState.tabAreaMode = (sidebarState.tabAreaMode == .downloads) ? .tabs : .downloads
    }

    /// Called when the user taps the history (clock) button in the sidebar
    var onToggleHistory: (() -> Void)?

    /// Called when the user cancels an in-progress download from the sidebar
    var onCancelDownload: (UUID) -> Void = { _ in }

    /// Called when the user pauses an in-progress download from the sidebar
    var onPauseDownload: (UUID) -> Void = { _ in }

    /// Called when the user resumes a paused download from the sidebar
    var onResumeDownload: (UUID) -> Void = { _ in }

    init(tabManager: TabManager, historyStore: HistoryStore, downloadStore: DownloadStore) {
        self.tabManager = tabManager
        self.historyStore = historyStore
        self.downloadStore = downloadStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarView = SidebarView(
            tabManager: tabManager,
            historyStore: historyStore,
            downloadStore: downloadStore,
            state: sidebarState,
            onToggleHistory: { [weak self] in
                self?.onToggleHistory?()
            },
            onCancelDownload: { [weak self] id in
                self?.onCancelDownload(id)
            },
            onPauseDownload: { [weak self] id in
                self?.onPauseDownload(id)
            },
            onResumeDownload: { [weak self] id in
                self?.onResumeDownload(id)
            }
        )
        hostingController = NSHostingController(rootView: sidebarView)
        hostingController.sizingOptions = []
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)

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
