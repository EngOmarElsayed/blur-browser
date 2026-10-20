import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable sudden termination so we get a chance to save session
        ProcessInfo.processInfo.disableSuddenTermination()

        AppMenuBuilder.buildMainMenu()

        // POC: confirm WebKit's ITP SPI is reachable before any windows open
        PrivacyReportService.enableITP()

        // One-time cleanup: older builds persisted all cookies (including
        // session cookies) to UserDefaults in plain text. That's a credential-
        // theft risk, so purge any leftover blob on launch. Cookie persistence
        // is now handled entirely by WKWebsiteDataStore.default(), which stores
        // them encrypted in the app's sandboxed container.
        UserDefaults.standard.removeObject(forKey: "persistedCookies")

        WebExtensionManager.shared.restore()
        #if DEBUG
        // `-BlurLoadExtension /path/to/unpacked` loads an extension for this run
        // (asks for consent like a normal install; not remembered).
        if let path = UserDefaults.standard.string(forKey: "BlurLoadExtension") {
            Task { try? await WebExtensionManager.shared.installUnpacked(at: URL(fileURLWithPath: path), remember: false) }
        }
        #endif

        openNewWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openNewWindow()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save session before quitting. Non-session cookies are persisted
        // automatically by WKWebsiteDataStore.default(); session cookies are
        // intentionally dropped on quit, matching the website's own intent.
        if let wc = windowController {
            TabSessionStore.save(tabManager: wc.tabManager)
            // Cancel any in-progress downloads so we don't leave orphan partial
            // files around. Documented choice: simplicity > resume-on-relaunch.
            wc.downloadManager.cancelAll()
        }

        return .terminateNow
    }

    // MARK: - Open URLs from external apps

    func application(_ application: NSApplication, open urls: [URL]) {
        // Ensure we have a window
        if windowController == nil {
            openNewWindow()
        }
        guard let wc = windowController else { return }

        for url in urls {
            wc.tabManager.addNewTab(url: url)
        }

        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.showSettings()
    }

    @objc func openNewWindow() {
        let wc = BrowserWindowController()
        wc.showWindow(nil)
        windowController = wc
    }

    @objc func newTab(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.newTabAndSearch()
    }

    @objc func openQuickSearch(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.openQuickSearch()
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        // ⌘W is forced to AppDelegate (otherwise WKWebView captures it).
        // That means we have to dispatch by key-window type ourselves —
        // for non-browser windows (Settings), close the window itself.
        let keyWindow = NSApp.keyWindow
        if keyWindow?.windowController is SettingsWindowController {
            keyWindow?.close()
            return
        }
        guard let wc = keyWindow?.windowController as? BrowserWindowController else { return }
        wc.closeCurrentTab()
    }

    @objc func focusSearch(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.focusAndSelectURLBar()
    }

    @objc func openFile(_ sender: Any?) {
        if windowController == nil { openNewWindow() }
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController
            ?? windowController else { return }
        wc.openFile()
    }

    @objc func copyURL(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.copyCurrentURL()
    }

    @objc func findInPage(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleFindInPage()
    }

    @objc func findNext(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.findPrevious()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleSidebar()
    }

    @objc func goBack(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.goForward()
    }

    @objc func reloadPage(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.reloadPage(bypassCache: false)
    }

    @objc func hardReload(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.reloadPage(bypassCache: true)
    }

    @objc func toggleHistory(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleHistory()
    }

    @objc func toggleAgent(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleAgentPanel()
    }

    @objc func focusMode(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.focusMode()
    }

    @objc func toggleAddressBar(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleAddressBar()
    }

    @objc func toggleInspector(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleInspector()
    }

    @objc func toggleEasyRead(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleReaderMode()
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.toggleShortcutsOverlay()
    }

    @objc func showDownloads(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.showDownloadsInSidebar()
    }

    @objc func selectTab1(_ sender: Any?) { selectTab(at: 0) }
    @objc func selectTab2(_ sender: Any?) { selectTab(at: 1) }
    @objc func selectTab3(_ sender: Any?) { selectTab(at: 2) }
    @objc func selectTab4(_ sender: Any?) { selectTab(at: 3) }
    @objc func selectTab5(_ sender: Any?) { selectTab(at: 4) }
    @objc func selectTab6(_ sender: Any?) { selectTab(at: 5) }
    @objc func selectTab7(_ sender: Any?) { selectTab(at: 6) }
    @objc func selectTab8(_ sender: Any?) { selectTab(at: 7) }
    @objc func selectTab9(_ sender: Any?) { selectTab(at: 8) }

    @objc func nextTab(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.nextTab()
    }

    @objc func previousTab(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.previousTab()
    }

    private func selectTab(at index: Int) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.selectTab(at: index)
    }
}

// MARK: - Extensions

extension AppDelegate: NSMenuDelegate {
    @objc func loadUnpackedExtension(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose an extension folder (the one containing manifest.json)"
        panel.prompt = "Load"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await installExtension { try await WebExtensionManager.shared.installUnpacked(at: url) } }
    }

    /// Pick an extension already installed in a Chromium browser on this Mac
    /// (Chrome, Arc, Brave, Edge, …) and load a copy of it. This is the easy
    /// way to get extensions like 1Password, whose Chrome ID must be kept.
    @objc func importChromiumExtension(_ sender: Any?) {
        let found = ChromeExtensionImporter.findInstalledChromiumExtensions()
        let alert = NSAlert()
        guard !found.isEmpty else {
            alert.messageText = "No Chromium extensions found"
            alert.informativeText = "Install the extension in Chrome, Arc, Brave or Edge first, or use Load Unpacked Extension…."
            alert.runModal()
            return
        }
        alert.messageText = "Import an extension"
        alert.informativeText = "Blur-Browser loads its own copy; the browser you import from isn't changed."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 26), pullsDown: false)
        for item in found {
            picker.addItem(withTitle: "\(item.name) \(item.version) — \(item.browser)")
        }
        if let onePassword = found.firstIndex(where: { $0.id == "aeblfdkhhhdcdjpifhhbdiojplfjncoa" }) {
            picker.selectItem(at: onePassword)
        }
        alert.accessoryView = picker
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let item = found[picker.indexOfSelectedItem]
        Task { await installExtension { try await WebExtensionManager.shared.installUnpacked(at: item.folder) } }
    }

    @objc func loadSafariExtension(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application, .applicationExtension]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app that contains a Safari web extension"
        panel.prompt = "Load"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await installExtension { try await WebExtensionManager.shared.installSafariExtensions(from: url) } }
    }

    private func installExtension(_ install: () async throws -> Void) async {
        do {
            try await install()
        } catch WebExtensionManager.ExtensionError.declined {
            return
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t load the extension"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Rebuilds Extensions › Remove Extension each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let installed = WebExtensionManager.shared.installed
        if installed.isEmpty {
            menu.addItem(withTitle: "No Extensions", action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        for item in installed {
            let menuItem = menu.addItem(withTitle: item.displayName, action: #selector(removeExtension(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id
        }
    }

    @objc private func removeExtension(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = WebExtensionManager.shared.installed.first(where: { $0.id == id }) else { return }
        WebExtensionManager.shared.uninstall(item)
    }
}
