import AppKit
import CryptoKit
import OSLog
import WebKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Blur-Browser", category: "Extensions")

/// Owns the app-wide `WKWebExtensionController`, the installed extensions,
/// and the delegate that maps WebKit's tabs/windows model onto `TabManager`.
///
/// Every tab's `WKWebViewConfiguration` gets `controller` (see
/// `BrowserTab.makeFilterConfiguration()`), so content scripts and the
/// `tabs`/`windows` APIs see every tab. Tab state still lives in `TabManager`;
/// `syncTabs(for:)` diffs it from the window's polling loop and reports the
/// changes to WebKit.
@Observable
@MainActor
final class WebExtensionManager: NSObject {
    static let shared = WebExtensionManager()

    /// Where an installed extension was loaded from. Persisted so extensions
    /// come back on the next launch.
    struct Source: Codable, Hashable {
        enum Kind: String, Codable { case folder, appExtension }
        var kind: Kind
        var path: String
        /// Stable per-install ID. Doubles as the context's `uniqueIdentifier`,
        /// which keys the extension's storage and its webkit-extension:// host.
        var id: String
        /// For unpacked extensions: the folder the user picked. `path` is then
        /// our managed copy with the Chrome compat shim (ChromeExtensionImporter).
        var origin: String?
    }

    struct Installed: Identifiable {
        let source: Source
        let context: WKWebExtensionContext
        var isRemembered = true
        var id: String { source.id }
        @MainActor var displayName: String { context.webExtension.displayName ?? URL(fileURLWithPath: source.path).lastPathComponent }
    }

    let controller: WKWebExtensionController
    private(set) var installed: [Installed] = []

    /// Bumped whenever an extension is added/removed or an action changes
    /// (icon, badge, enabled). The window's polling loop watches it to
    /// rebuild the toolbar buttons.
    private(set) var actionsRevision = 0

    /// Toolbar buttons register themselves here so popups anchor under the
    /// button that was clicked.
    var popupAnchor: ((WKWebExtensionContext) -> NSView?)?

    @ObservationIgnored private var windows: [ObjectIdentifier: ExtensionWindow] = [:]
    @ObservationIgnored private var tabAdapters: [UUID: ExtensionTab] = [:]
    @ObservationIgnored private var tabSnapshots: [ObjectIdentifier: WindowSnapshot] = [:]
    @ObservationIgnored private let nativeMessaging = NativeMessagingBridge()
    /// Windows opened by `windows.create` — nothing else retains their controllers.
    @ObservationIgnored private var extensionOpenedWindows: [BrowserWindowController] = []

    private static let sourcesKey = "webExtensions.sources"
    private static let controllerIDKey = "webExtensions.controllerID"
    private static let approvedKey = "webExtensions.approved"

    override private init() {
        let defaults = UserDefaults.standard
        let controllerID: UUID
        if let stored = defaults.string(forKey: Self.controllerIDKey), let uuid = UUID(uuidString: stored) {
            controllerID = uuid
        } else {
            controllerID = UUID()
            defaults.set(controllerID.uuidString, forKey: Self.controllerIDKey)
        }
        // Persistent storage (extension local storage, granted permissions, etc.).
        let configuration = WKWebExtensionController.Configuration(identifier: controllerID)
        configuration.defaultWebsiteDataStore = .default()
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    // MARK: - Install / restore

    /// Load every extension saved from a previous launch.
    func restore() {
        for source in Self.savedSources() {
            Task {
                do { try await load(source, isNewInstall: false) }
                catch { logger.error("Couldn't load extension at \(source.path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
            }
        }
        #if DEBUG
        Task {
            try? await Task.sleep(for: .seconds(10))
            logState()
        }
        // Shell-triggerable hooks for debugging without clicking: post
        // "BlurDebugLogState" (log tabs/errors/popup) or "BlurDebugPerformAction"
        // (click the first extension's toolbar button) on the distributed
        // notification center.
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("BlurDebugLogState"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WebExtensionManager.shared.logState() }
        }
        center.addObserver(forName: Notification.Name("BlurDebugPerformAction"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let manager = WebExtensionManager.shared
                guard let item = manager.installed.first, let wc = manager.focusedWindowController else { return }
                manager.performAction(for: item.context, in: wc)
            }
        }
        #endif
    }

    #if DEBUG
    @ObservationIgnored private var lastPopupWebView: WKWebView?
    #endif

    @ObservationIgnored private var loggedErrorCounts: [String: Int] = [:]

    /// Debug aid: what WebKit thinks is open, next to what TabManager has.
    func logState() {
        let appTabs = windows.values.compactMap(\.windowController).flatMap { $0.tabManager.tabs }
        logger.notice("App: \(self.windows.count) windows, \(appTabs.count) tabs")
        for item in installed {
            let context = item.context
            let open = context.openTabs.compactMap { ($0 as? ExtensionTab) }
            let matched = open.filter { adapter in appTabs.contains { $0.webView === adapter.tab?.webView } }
            logger.notice("\(item.displayName, privacy: .public) \(context.baseURL.absoluteString, privacy: .public): loaded=\(context.isLoaded) windows=\(context.openWindows.count) tabs=\(open.count) matched=\(matched.count) errors=\(context.errors.count)")
            let errors = context.errors
            let start = loggedErrorCounts[item.id] ?? 0
            for error in errors.dropFirst(min(start, errors.count)) {
                logger.notice("  error: \(error.localizedDescription, privacy: .public)")
            }
            loggedErrorCounts[item.id] = errors.count
            #if DEBUG
            let knownWebViews = Set(open.compactMap { $0.tab?.webView }.map(ObjectIdentifier.init))
            for tab in appTabs where !knownWebViews.contains(ObjectIdentifier(tab.webView)) {
                logger.notice("  tab unknown to WebKit: \(tab.url?.absoluteString ?? "nil", privacy: .public)")
            }
            if let popup = lastPopupWebView {
                logger.notice("  popup: url=\(popup.url?.absoluteString ?? "nil", privacy: .public) frame=\(String(describing: popup.frame), privacy: .public) window=\(popup.window != nil)")
                popup.evaluateJavaScript("document.body ? document.body.innerText.slice(0, 400) : ''") { result, error in
                    logger.notice("  popup text: \(String(describing: result), privacy: .public) \(String(describing: error), privacy: .public)")
                }
            }
            #endif
        }
    }

    /// Whether any extension is saved for loading at launch. Readable before
    /// `restore()` finishes, so the first tabs' configuration can depend on it.
    static var hasSavedExtensions: Bool { !savedSources().isEmpty }

    /// Load an unpacked extension (a folder containing manifest.json). It's
    /// copied into a managed folder with the Chrome compat shim applied.
    func installUnpacked(at folder: URL, remember: Bool = true) async throws {
        let origin = folder.standardizedFileURL.path
        if installed.contains(where: { $0.source.origin == origin || $0.source.path == origin }) {
            throw ExtensionError.alreadyInstalled
        }
        let id = UUID().uuidString
        let copy = try ChromeExtensionImporter.prepareManagedCopy(of: folder, installID: id)
        let source = Source(kind: .folder, path: copy.path, id: id, origin: origin)
        do {
            try await load(source, isNewInstall: true, remember: remember)
        } catch {
            ChromeExtensionImporter.removeManagedCopy(at: copy)
            throw error
        }
    }

    /// Load the Safari web extensions bundled inside an app (or a single .appex).
    /// Returns the number of extensions loaded.
    @discardableResult
    func installSafariExtensions(from bundleURL: URL) async throws -> Int {
        let appexes: [URL]
        if bundleURL.pathExtension == "appex" {
            appexes = [bundleURL]
        } else {
            appexes = Self.safariWebExtensions(inApp: bundleURL)
        }
        guard !appexes.isEmpty else { throw ExtensionError.noSafariExtension(bundleURL.lastPathComponent) }
        var loaded = 0
        for appex in appexes {
            let source = Source(kind: .appExtension, path: appex.standardizedFileURL.path, id: UUID().uuidString)
            try await load(source, isNewInstall: true)
            loaded += 1
        }
        return loaded
    }

    func uninstall(_ item: Installed) {
        try? controller.unload(item.context)
        if item.source.kind == .folder {
            ChromeExtensionImporter.removeManagedCopy(at: URL(fileURLWithPath: item.source.path))
        }
        installed.removeAll { $0.id == item.id }
        Self.saveSources(installed.filter(\.isRemembered).map(\.source))
        var approved = Self.approvedIDs()
        approved.remove(item.id)
        UserDefaults.standard.set(Array(approved), forKey: Self.approvedKey)
        actionsRevision += 1
    }

    private func load(_ source: Source, isNewInstall: Bool, remember: Bool = true) async throws {
        if installed.contains(where: { $0.source.path == source.path }) {
            throw ExtensionError.alreadyInstalled
        }
        let url = URL(fileURLWithPath: source.path)
        let webExtension: WKWebExtension
        switch source.kind {
        case .folder:
            webExtension = try await WKWebExtension(resourceBaseURL: url)
        case .appExtension:
            guard let bundle = Bundle(url: url) else { throw ExtensionError.unreadable(source.path) }
            webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        }

        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = source.id
        // A stable base URL (WebKit picks a random one per launch otherwise),
        // so restored tabs showing the extension's pages still resolve.
        if let baseURL = URL(string: "webkit-extension://\(source.id.lowercased())/") {
            context.baseURL = baseURL
        }
        #if DEBUG
        context.isInspectable = true
        #endif

        // Ask once, at install time, for everything the manifest requests.
        // On later launches re-grant what the user already approved.
        let approved = Self.approvedIDs().contains(source.id)
        if !approved {
            guard isNewInstall, confirmInstall(of: webExtension) else { throw ExtensionError.declined }
            if remember {
                var ids = Self.approvedIDs()
                ids.insert(source.id)
                UserDefaults.standard.set(Array(ids), forKey: Self.approvedKey)
            }
        }
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }

        try controller.load(context)
        installed.append(Installed(source: source, context: context, isRemembered: remember))
        reopenExtensionPages(of: context)
        if isNewInstall { Self.saveSources(installed.filter(\.isRemembered).map(\.source)) }
        actionsRevision += 1
    }

    private func confirmInstall(of webExtension: WKWebExtension) -> Bool {
        let alert = NSAlert()
        let name = webExtension.displayName ?? "This extension"
        alert.messageText = "Add “\(name)”?"
        var lines: [String] = []
        let hosts = webExtension.allRequestedMatchPatterns.map(\.description).sorted()
        if !hosts.isEmpty {
            lines.append("It can read and change content on: " + hosts.joined(separator: ", "))
        }
        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        if !permissions.isEmpty {
            lines.append("Permissions: " + permissions.joined(separator: ", "))
        }
        alert.informativeText = lines.isEmpty ? "It requests no special permissions." : lines.joined(separator: "\n\n")
        if let icon = webExtension.icon(for: CGSize(width: 64, height: 64)) { alert.icon = icon }
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Windows and tabs

    func register(_ windowController: BrowserWindowController) {
        let window = ExtensionWindow(windowController: windowController)
        windows[ObjectIdentifier(windowController)] = window
        controller.didOpenWindow(window)
        syncTabs(for: windowController)
    }

    func unregister(_ windowController: BrowserWindowController) {
        let key = ObjectIdentifier(windowController)
        guard let window = windows.removeValue(forKey: key) else { return }
        for id in tabSnapshots.removeValue(forKey: key)?.order ?? [] {
            if let adapter = tabAdapters.removeValue(forKey: id) {
                controller.didCloseTab(adapter, windowIsClosing: true)
            }
        }
        controller.didCloseWindow(window)
        extensionOpenedWindows.removeAll { $0 === windowController }
    }

    func windowDidBecomeKey(_ windowController: BrowserWindowController) {
        controller.didFocusWindow(windows[ObjectIdentifier(windowController)])
    }

    /// The stable adapter WebKit sees for `tab`.
    func adapter(for tab: BrowserTab) -> ExtensionTab {
        if let existing = tabAdapters[tab.id] { return existing }
        let adapter = ExtensionTab(tab: tab, window: windowAdapter(containing: tab))
        tabAdapters[tab.id] = adapter
        return adapter
    }

    private func windowAdapter(containing tab: BrowserTab) -> ExtensionWindow? {
        windows.values.first { $0.windowController?.tabManager.tabs.contains(tab) == true }
    }

    private struct TabState: Equatable {
        var url: URL?
        var title: String
        var isLoading: Bool
        var isPinned: Bool
    }

    private struct WindowSnapshot {
        var order: [UUID] = []
        var selected: UUID?
        var states: [UUID: TabState] = [:]
    }

    /// Diff the window's tabs against the last snapshot and tell WebKit what
    /// changed. Called from the window's 50ms polling loop.
    func syncTabs(for windowController: BrowserWindowController) {
        let key = ObjectIdentifier(windowController)
        guard let window = windows[key] else { return }
        let tabManager = windowController.tabManager
        var snapshot = tabSnapshots[key] ?? WindowSnapshot()

        let currentIDs = tabManager.tabs.map(\.id)
        let current = Set(currentIDs)

        for id in snapshot.order where !current.contains(id) {
            if let adapter = tabAdapters.removeValue(forKey: id) {
                controller.didCloseTab(adapter, windowIsClosing: false)
            }
            snapshot.states[id] = nil
        }

        for tab in tabManager.tabs {
            let state = TabState(url: tab.url, title: tab.title, isLoading: tab.isLoading, isPinned: tab.isPinned)
            let adapter = adapter(for: tab)
            adapter.window = window
            guard let previous = snapshot.states[tab.id] else {
                controller.didOpenTab(adapter)
                snapshot.states[tab.id] = state
                continue
            }
            guard previous != state else { continue }
            var changed: WKWebExtension.TabChangedProperties = []
            if previous.url != state.url { changed.insert(.URL) }
            if previous.title != state.title { changed.insert(.title) }
            if previous.isLoading != state.isLoading { changed.insert(.loading) }
            if previous.isPinned != state.isPinned { changed.insert(.pinned) }
            controller.didChangeTabProperties(changed, for: adapter)
            snapshot.states[tab.id] = state
        }

        let previousOrder = snapshot.order.filter(current.contains)
        if previousOrder != currentIDs.filter(Set(previousOrder).contains) {
            for (index, id) in currentIDs.enumerated() {
                guard let oldIndex = previousOrder.firstIndex(of: id), oldIndex != index,
                      let adapter = tabAdapters[id] else { continue }
                controller.didMoveTab(adapter, from: oldIndex, in: window)
            }
        }
        snapshot.order = currentIDs

        if tabManager.selectedTabID != snapshot.selected {
            let previous = snapshot.selected.flatMap { tabAdapters[$0] }
            if let tab = tabManager.selectedTab {
                controller.didActivateTab(adapter(for: tab), previousActiveTab: previous)
            }
            snapshot.selected = tabManager.selectedTabID
            actionsRevision += 1 // per-tab action state (badge, enabled) may differ
        }

        tabSnapshots[key] = snapshot
    }

    private var focusedWindowController: BrowserWindowController? {
        if let wc = NSApp.keyWindow?.windowController as? BrowserWindowController { return wc }
        if let wc = NSApp.mainWindow?.windowController as? BrowserWindowController { return wc }
        return windows.values.lazy.compactMap(\.windowController).first
    }

    // MARK: - Extension pages in tabs

    func webViewConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard url.scheme == "webkit-extension" else { return nil }
        return controller.extensionContext(for: url)?.webViewConfiguration
    }

    /// Whether navigating `tab` to `url` crosses into or out of an extension's
    /// pages, which needs a web view built from a different configuration.
    func needsWebViewSwap(for tab: BrowserTab, to url: URL) -> Bool {
        let target = webViewConfiguration(for: url) == nil ? nil : url.host
        return target != tab.extensionPageHost
    }

    /// Tabs restored before the extension loaded got a plain web view; give
    /// them the extension's configuration now.
    private func reopenExtensionPages(of context: WKWebExtensionContext) {
        guard let host = context.baseURL.host else { return }
        for windowController in windows.values.compactMap(\.windowController) {
            for tab in windowController.tabManager.tabs
            where tab.url?.host == host && tab.extensionPageHost != host {
                if let url = tab.url { windowController.tabManager.replaceTab(tab, loading: url) }
            }
        }
    }

    // MARK: - Actions

    /// Run the extension's toolbar action for the selected tab. WebKit calls
    /// back into `presentActionPopup` if the action has a popup.
    func performAction(for context: WKWebExtensionContext, in windowController: BrowserWindowController) {
        let tab = windowController.tabManager.selectedTab.map { adapter(for: $0) }
        context.performAction(for: tab)
    }

    func action(for context: WKWebExtensionContext, in windowController: BrowserWindowController) -> WKWebExtension.Action? {
        let tab = windowController.tabManager.selectedTab.map { adapter(for: $0) }
        return context.action(for: tab)
    }

    // MARK: - Saved state

    private static func savedSources() -> [Source] {
        guard let data = UserDefaults.standard.data(forKey: sourcesKey) else { return [] }
        return (try? JSONDecoder().decode([Source].self, from: data)) ?? []
    }

    private static func saveSources(_ sources: [Source]) {
        if let data = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(data, forKey: sourcesKey)
        }
    }

    private static func approvedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: approvedKey) ?? [])
    }

    /// Safari web extensions (`com.apple.Safari.web-extension`) inside an app's PlugIns folder.
    static func safariWebExtensions(inApp appURL: URL) -> [URL] {
        let plugIns = appURL.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? []
        return items.filter { url in
            guard url.pathExtension == "appex",
                  let info = Bundle(url: url)?.infoDictionary,
                  let ext = info["NSExtension"] as? [String: Any],
                  let point = ext["NSExtensionPointIdentifier"] as? String else { return false }
            return point == "com.apple.Safari.web-extension"
        }
    }

    /// Chrome derives an extension's ID from the manifest `key` (base64 DER
    /// public key): first 128 bits of its SHA-256, hex digits mapped to a–p.
    /// Native messaging hosts list allowed origins by this ID.
    static func chromeExtensionID(for webExtension: WKWebExtension) -> String? {
        guard let key = webExtension.manifest["key"] as? String,
              let der = Data(base64Encoded: key) else { return nil }
        let digest = SHA256.hash(data: der)
        let letters = Array("abcdefghijklmnop")
        return digest.prefix(16).map { byte in
            String([letters[Int(byte >> 4)], letters[Int(byte & 0x0F)]])
        }.joined()
    }

    enum ExtensionError: LocalizedError {
        case alreadyInstalled, declined
        case unreadable(String)
        case noSafariExtension(String)

        var errorDescription: String? {
            switch self {
            case .alreadyInstalled: "That extension is already installed."
            case .declined: "The extension wasn't added."
            case .unreadable(let path): "Couldn't read the extension at \(path)."
            case .noSafariExtension(let name): "\(name) doesn't contain a Safari web extension."
            }
        }
    }
}

// MARK: - WKWebExtensionControllerDelegate

extension WebExtensionManager: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        // Focused window first, as WebKit expects.
        let focused = focusedWindowController.flatMap { windows[ObjectIdentifier($0)] }
        let others = windows.values.filter { $0 !== focused && $0.windowController != nil }
        return (focused.map { [$0] } ?? []) + others
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        focusedWindowController.flatMap { windows[ObjectIdentifier($0)] }
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        let target = (configuration.window as? ExtensionWindow)?.windowController ?? focusedWindowController
        guard let windowController = target else { return completionHandler(nil, nil) }
        let tabManager = windowController.tabManager
        let previousSelection = tabManager.selectedTab
        let tab = tabManager.addNewTab(url: configuration.url)
        if configuration.shouldBePinned { tabManager.pinTab(tab) }
        if !configuration.shouldBeActive, let previousSelection { tabManager.selectTab(previousSelection) }
        let adapter = adapter(for: tab)
        syncTabs(for: windowController)
        completionHandler(adapter, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionWindow)?, Error?) -> Void) {
        let windowController = BrowserWindowController()
        extensionOpenedWindows.append(windowController)
        if configuration.frame != .null, !configuration.frame.isEmpty {
            windowController.window?.setFrame(configuration.frame, display: false)
        }
        windowController.showWindow(nil)
        let tabManager = windowController.tabManager
        let blank = tabManager.tabs
        for url in configuration.tabURLs { tabManager.addNewTab(url: url, afterCurrent: false) }
        // Replace the default new-tab tab when the extension asked for specific URLs.
        if !configuration.tabURLs.isEmpty {
            for tab in blank where tab.url == AppConstants.newTabURL && !tab.isPinned { tabManager.closeTab(tab) }
        }
        syncTabs(for: windowController)
        completionHandler(windows[ObjectIdentifier(windowController)], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let url = extensionContext.optionsPageURL {
            focusedWindowController?.tabManager.addNewTab(url: url)
        }
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let names = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        let granted = askForPermission(extensionContext, detail: "It wants these additional permissions: \(names).")
        completionHandler(granted ? permissions : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let hosts = Set(urls.compactMap(\.host)).sorted().joined(separator: ", ")
        let granted = askForPermission(extensionContext, detail: "It wants to read and change content on \(hosts).")
        completionHandler(granted ? urls : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let patterns = matchPatterns.map(\.description).sorted().joined(separator: ", ")
        let granted = askForPermission(extensionContext, detail: "It wants to read and change content on \(patterns).")
        completionHandler(granted ? matchPatterns : [], nil)
    }

    private func askForPermission(_ context: WKWebExtensionContext, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow “\(context.webExtension.displayName ?? "extension")”?"
        alert.informativeText = detail
        if let icon = context.webExtension.icon(for: CGSize(width: 64, height: 64)) { alert.icon = icon }
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        actionsRevision += 1
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        #if DEBUG
        lastPopupWebView = action.popupWebView
        logger.notice("presentActionPopup: popover=\(action.popupPopover != nil) webView=\(action.popupWebView != nil) shown=\(action.popupPopover?.isShown ?? false) anchor=\(self.popupAnchor?(context) != nil) keyWindow=\(NSApp.keyWindow != nil) active=\(NSApp.isActive)")
        #endif
        guard let popover = action.popupPopover,
              let anchor = popupAnchor?(context) ?? focusedWindowController?.window?.contentView else {
            return completionHandler(nil)
        }
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, Error?) -> Void) {
        if (applicationIdentifier ?? "").isEmpty, usesSafariNativeShim(extensionContext) {
            do { replyHandler(try SafariNativeShim.reply(to: message), nil) } catch { replyHandler(nil, error) }
            return
        }
        nativeMessaging.sendMessage(message, toHost: applicationIdentifier, from: extensionContext, replyHandler: replyHandler)
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if (port.applicationIdentifier ?? "").isEmpty, usesSafariNativeShim(extensionContext) {
            SafariNativeShim.acceptQuietPort(port)
            return completionHandler(nil)
        }
        nativeMessaging.connect(port, from: extensionContext, completionHandler: completionHandler)
    }

    /// Safari web extensions whose app-extension handler we stand in for
    /// (see SafariNativeShim).
    private func usesSafariNativeShim(_ context: WKWebExtensionContext) -> Bool {
        guard let source = installed.first(where: { $0.context === context })?.source,
              source.kind == .appExtension,
              let bundleID = Bundle(path: source.path)?.bundleIdentifier else { return false }
        return SafariNativeShim.supportedBundleIDs.contains(bundleID)
    }
}
