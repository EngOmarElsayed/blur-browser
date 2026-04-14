import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenuBuilder.buildMainMenu()
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
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.closeCurrentTab()
    }

    @objc func focusSearch(_ sender: Any?) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.focusAndSelectURLBar()
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
