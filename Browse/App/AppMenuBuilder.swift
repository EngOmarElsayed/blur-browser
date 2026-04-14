import AppKit

enum AppMenuBuilder {

    @MainActor
    static func buildMainMenu() {
        let mainMenu = NSMenu()
        let delegate = NSApp.delegate as? AppDelegate

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(AppConstants.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(AppConstants.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(AppConstants.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        addItem(to: fileMenu, title: "New Tab", action: #selector(AppDelegate.newTab(_:)), key: "t", target: delegate)
        addItem(to: fileMenu, title: "Quick Search", action: #selector(AppDelegate.openQuickSearch(_:)), key: "k", target: delegate)
        addItem(to: fileMenu, title: "New Window", action: #selector(AppDelegate.openNewWindow), key: "n", target: delegate)
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, title: "Open Location...", action: #selector(AppDelegate.focusSearch(_:)), key: "l", target: delegate)
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, title: "Close Tab", action: #selector(AppDelegate.closeCurrentTab(_:)), key: "w", target: delegate)
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        addItem(to: editMenu, title: "Find...", action: #selector(AppDelegate.findInPage(_:)), key: "f", target: delegate)
        addItem(to: editMenu, title: "Find Next", action: #selector(AppDelegate.findNext(_:)), key: "g", target: delegate)
        addItem(to: editMenu, title: "Find Previous", action: #selector(AppDelegate.findPrevious(_:)), key: "G", modifiers: [.command, .shift], target: delegate)
        editMenu.addItem(.separator())
        addItem(to: editMenu, title: "Copy URL", action: #selector(AppDelegate.copyURL(_:)), key: "C", modifiers: [.command, .shift], target: delegate)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        addItem(to: viewMenu, title: "Toggle Sidebar", action: #selector(AppDelegate.toggleSidebar(_:)), key: "\\", target: delegate)
        viewMenu.addItem(.separator())
        addItem(to: viewMenu, title: "Reload", action: #selector(AppDelegate.reloadPage(_:)), key: "r", target: delegate)
        addItem(to: viewMenu, title: "Hard Reload", action: #selector(AppDelegate.hardReload(_:)), key: "R", modifiers: [.command, .shift], target: delegate)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // History menu
        let historyMenu = NSMenu(title: "History")
        addItem(to: historyMenu, title: "Show History", action: #selector(AppDelegate.toggleHistory(_:)), key: "y", target: delegate)
        historyMenu.addItem(.separator())
        addItem(to: historyMenu, title: "Back", action: #selector(AppDelegate.goBack(_:)), key: "[", target: delegate)
        addItem(to: historyMenu, title: "Forward", action: #selector(AppDelegate.goForward(_:)), key: "]", target: delegate)
        let historyMenuItem = NSMenuItem()
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        addItem(to: windowMenu, title: "Show Next Tab", action: #selector(AppDelegate.nextTab(_:)), key: "]", modifiers: [.command, .shift], target: delegate)
        addItem(to: windowMenu, title: "Show Previous Tab", action: #selector(AppDelegate.previousTab(_:)), key: "[", modifiers: [.command, .shift], target: delegate)
        windowMenu.addItem(.separator())

        // Tab shortcuts 1-9
        let tabSelectors: [Selector] = [
            #selector(AppDelegate.selectTab1(_:)), #selector(AppDelegate.selectTab2(_:)),
            #selector(AppDelegate.selectTab3(_:)), #selector(AppDelegate.selectTab4(_:)),
            #selector(AppDelegate.selectTab5(_:)), #selector(AppDelegate.selectTab6(_:)),
            #selector(AppDelegate.selectTab7(_:)), #selector(AppDelegate.selectTab8(_:)),
            #selector(AppDelegate.selectTab9(_:))
        ]
        for i in 1...9 {
            addItem(to: windowMenu, title: "Tab \(i)", action: tabSelectors[i - 1], key: "\(i)", target: delegate)
        }

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Helper

    @discardableResult
    private static func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject?
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
