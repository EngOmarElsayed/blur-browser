import Foundation

struct TabSession: Codable {
    let url: String
    let title: String
}

struct SessionData: Codable {
    let tabs: [TabSession]
    let selectedIndex: Int
}

@MainActor
enum TabSessionStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppConstants.appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    static func save(tabManager: TabManager) {
        // Only save unpinned tabs — pinned tabs are persisted via SwiftData
        let unpinnedTabs = tabManager.tabs.filter { !$0.isPinned }
        let tabs = unpinnedTabs.map {
            TabSession(url: $0.url?.absoluteString ?? "", title: $0.title)
        }

        // Find selected index among unpinned tabs
        let selectedIndex: Int
        if let selectedTab = tabManager.selectedTab, !selectedTab.isPinned {
            selectedIndex = unpinnedTabs.firstIndex(of: selectedTab).map { $0 } ?? 0
        } else {
            selectedIndex = 0
        }

        let session = SessionData(tabs: tabs, selectedIndex: selectedIndex)

        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save session: \(error)")
        }
    }

    static func restore(into tabManager: TabManager) {
        guard let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data),
              !session.tabs.isEmpty
        else { return }

        // Clear default tab
        tabManager.tabs.removeAll()

        for tabSession in session.tabs {
            let url = URL(string: tabSession.url)
            let tab = tabManager.addNewTab(url: url, afterCurrent: false)
            tab.title = tabSession.title
        }

        let idx = min(session.selectedIndex, tabManager.tabs.count - 1)
        if idx >= 0 {
            tabManager.selectTab(at: idx)
        }
    }
}
