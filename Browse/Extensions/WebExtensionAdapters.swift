import AppKit
import WebKit

/// Presents a `BrowserTab` to web extensions. `BrowserTab` isn't an NSObject,
/// so `WebExtensionManager` keeps one adapter per tab ID — WebKit relies on
/// the same object coming back every time for the same tab.
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    private(set) weak var tab: BrowserTab?
    weak var window: ExtensionWindow?

    init(tab: BrowserTab, window: ExtensionWindow?) {
        self.tab = tab
        self.window = window
    }

    private var tabManager: TabManager? { window?.windowController?.tabManager }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let tab, let index = tabManager?.tabs.firstIndex(of: tab) else { return NSNotFound }
        return index
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { tab?.webView }

    func title(for context: WKWebExtensionContext) -> String? { tab?.title }

    func url(for context: WKWebExtensionContext) -> URL? { tab?.webView.url ?? tab?.url }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(tab?.isLoading ?? false) }

    func isPinned(for context: WKWebExtensionContext) -> Bool { tab?.isPinned ?? false }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        guard let tab else { return false }
        return tabManager?.selectedTabID == tab.id
    }

    func isReaderModeActive(for context: WKWebExtensionContext) -> Bool { tab?.readerArticle != nil }

    func size(for context: WKWebExtensionContext) -> CGSize { tab?.webView.bounds.size ?? .zero }

    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(tab?.webView.pageZoom ?? 1) }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab?.webView.pageZoom = zoomFactor
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let tab else { return completionHandler(nil) }
        tab.url = url
        BrowserTab.load(url, on: tab.webView)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if fromOrigin { tab?.webView.reloadFromOrigin() } else { tab?.webView.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab?.webView.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab?.webView.goForward()
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let tab { tabManager?.selectTab(tab) }
        window?.windowController?.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        // Single selection only: selecting a tab activates it.
        if selected, let tab { tabManager?.selectTab(tab) }
        completionHandler(nil)
    }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let tab, let tabManager {
            if pinned { tabManager.pinTab(tab) } else { tabManager.unpinTab(tab) }
        }
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let tab, let tabManager {
            // Extensions may close pinned tabs; TabManager refuses those, so unpin first.
            if tab.isPinned { tabManager.unpinTab(tab) }
            tabManager.closeTab(tab)
        }
        completionHandler(nil)
    }

    func duplicate(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        guard let tab, let tabManager else { return completionHandler(nil, nil) }
        let copy = tabManager.duplicateTab(tab)
        completionHandler(WebExtensionManager.shared.adapter(for: copy), nil)
    }

    func takeSnapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping (NSImage?, Error?) -> Void) {
        guard let webView = tab?.webView else { return completionHandler(nil, nil) }
        webView.takeSnapshot(with: configuration) { image, error in
            completionHandler(image, error)
        }
    }

    /// Clicking the toolbar button counts as a user gesture, which grants
    /// `activeTab`-style access for this tab.
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }
}

/// Presents a `BrowserWindowController` to web extensions.
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    private(set) weak var windowController: BrowserWindowController?

    init(windowController: BrowserWindowController) {
        self.windowController = windowController
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let tabManager = windowController?.tabManager else { return [] }
        return tabManager.tabs.map { WebExtensionManager.shared.adapter(for: $0) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let tab = windowController?.tabManager.selectedTab else { return nil }
        return WebExtensionManager.shared.adapter(for: tab)
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = windowController?.window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isZoomed { return .maximized }
        return .normal
    }

    func setWindowState(_ state: WKWebExtension.WindowState, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let window = windowController?.window else { return completionHandler(nil) }
        switch state {
        case .minimized: window.miniaturize(nil)
        case .maximized: if !window.isZoomed { window.zoom(nil) }
        case .fullscreen: if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        default:
            if window.isMiniaturized { window.deminiaturize(nil) }
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        completionHandler(nil)
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        windowController?.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        windowController?.window?.frame ?? .null
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        windowController?.window?.setFrame(frame, display: true)
        completionHandler(nil)
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        windowController?.window?.performClose(nil)
        completionHandler(nil)
    }
}
