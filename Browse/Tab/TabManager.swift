import AppKit
import Observation

@Observable
@MainActor
final class TabManager {
    var tabs: [BrowserTab] = []
    var selectedTabID: UUID?

    private let pinnedStore = PinnedTabStore()

    var selectedTab: BrowserTab? {
        guard let id = selectedTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var selectedIndex: Int? {
        guard let id = selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    // MARK: - Pinned / Unpinned Computed Lists

    var pinnedTabs: [BrowserTab] {
        tabs.filter { $0.isPinned }
    }

    var unpinnedTabs: [BrowserTab] {
        tabs.filter { !$0.isPinned }
    }

    init() {
        addNewTab(url: URL(string: AppConstants.newTabURL))
    }

    @discardableResult
    func addNewTab(url: URL? = nil, afterCurrent: Bool = true) -> BrowserTab {
        let resolvedURL = url ?? URL(string: AppConstants.newTabURL)
        let tab = BrowserTab(url: resolvedURL)
        if afterCurrent, let idx = selectedIndex {
            tabs.insert(tab, at: idx + 1)
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
        return tab
    }

    func closeTab(_ tab: BrowserTab) {
        // Pinned tabs cannot be closed — must unpin first
        if tab.isPinned { return }

        guard let index = tabs.firstIndex(of: tab) else { return }
        let wasSelected = tab.id == selectedTabID

        // Stop any active media capture before closing
        let wv = tab.webView
        if wv.cameraCaptureState != .none {
            wv.setCameraCaptureState(.none)
        }
        if wv.microphoneCaptureState != .none {
            wv.setMicrophoneCaptureState(.none)
        }

        // Stop any media playback (audio/video) before the tab goes away.
        // WKWebView retains the media session even after removal from the view
        // hierarchy, so we have to explicitly pause. `pauseAllMediaPlayback`
        // handles HTML5 video/audio across all frames.
        wv.pauseAllMediaPlayback()
        // Also load about:blank to tear down the page entirely (safety net for
        // sites that drive audio via Web Audio or other non-media-element paths).
        wv.load(URLRequest(url: URL(string: "about:blank")!))

        tabs.remove(at: index)

        if wasSelected {
            if tabs.isEmpty {
                addNewTab()
            } else {
                let newIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[newIndex].id
            }
        }
    }

    func closeOtherTabs(except tab: BrowserTab) {
        // Keep pinned tabs and the excepted tab
        tabs.removeAll { $0.id != tab.id && !$0.isPinned }
        selectedTabID = tab.id
    }

    @discardableResult
    func duplicateTab(_ tab: BrowserTab) -> BrowserTab {
        addNewTab(url: tab.url)
    }

    // MARK: - Pin / Unpin

    func pinTab(_ tab: BrowserTab) {
        guard !tab.isPinned else { return }
        tab.isPinned = true
        // Move pinned tab to end of pinned section
        guard let index = tabs.firstIndex(of: tab) else { return }
        let pinnedCount = tabs.filter { $0.isPinned && $0.id != tab.id }.count
        tabs.remove(at: index)
        tabs.insert(tab, at: pinnedCount)
        // Force @Observable to re-emit
        tabs = Array(tabs)

        // Persist to SwiftData (keyed by URL, not tab ID)
        let orderIndex = pinnedCount
        pinnedStore.savePinnedTab(
            url: tab.url?.absoluteString ?? "",
            title: tab.title,
            orderIndex: orderIndex
        )
    }

    func unpinTab(_ tab: BrowserTab) {
        guard tab.isPinned else { return }
        tab.isPinned = false
        // Move unpinned tab to top of unpinned section (right after last pinned tab)
        guard let index = tabs.firstIndex(of: tab) else { return }
        let pinnedCount = tabs.filter { $0.isPinned }.count
        tabs.remove(at: index)
        tabs.insert(tab, at: pinnedCount)
        // Force @Observable to re-emit
        tabs = Array(tabs)

        // Remove from SwiftData (keyed by URL)
        pinnedStore.removePinnedTab(url: tab.url?.absoluteString ?? "")
    }

    // MARK: - Restore Pinned Tabs from SwiftData

    func restorePinnedTabs() {
        let entries = pinnedStore.fetchAll()
        guard !entries.isEmpty else { return }

        for entry in entries {
            let url = URL(string: entry.url)
            let tab = BrowserTab(url: url)
            tab.isPinned = true
            tab.title = entry.title
            // Insert at the front (pinned tabs go before unpinned)
            let pinnedCount = tabs.filter { $0.isPinned }.count
            tabs.insert(tab, at: pinnedCount)
        }

        // Select the first tab if nothing is selected
        if selectedTabID == nil, let first = tabs.first {
            selectedTabID = first.id
        }

        tabs = Array(tabs)
    }

    // MARK: - Sync pinned tab order to SwiftData

    func savePinnedTabOrder() {
        let pinned = pinnedTabs
        let orderUpdates = pinned.enumerated().map { (index, tab) in
            (url: tab.url?.absoluteString ?? "", orderIndex: index)
        }
        pinnedStore.updateOrder(tabs: orderUpdates)
    }

    // MARK: - Selection

    func selectTab(_ tab: BrowserTab) {
        selectedTabID = tab.id
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedTabID = tabs[index].id
    }

    func selectNextTab() {
        guard let idx = selectedIndex else { return }
        let next = (idx + 1) % tabs.count
        selectedTabID = tabs[next].id
    }

    func selectPreviousTab() {
        guard let idx = selectedIndex else { return }
        let prev = (idx - 1 + tabs.count) % tabs.count
        selectedTabID = tabs[prev].id
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    func movePinnedTab(from source: IndexSet, to destination: Int) {
        // Remap indices within pinned section to full tabs array
        let pinned = pinnedTabs
        var pinnedIndices: [Int] = []
        for idx in source {
            if let fullIdx = tabs.firstIndex(where: { $0.id == pinned[idx].id }) {
                pinnedIndices.append(fullIdx)
            }
        }
        // Simple swap for single item moves
        guard let fromIdx = pinnedIndices.first else { return }
        let toIdx = min(destination, pinnedTabs.count)
        if fromIdx != toIdx {
            let tab = tabs.remove(at: fromIdx)
            let insertAt = min(toIdx, tabs.count)
            tabs.insert(tab, at: insertAt)
        }
        // Persist reordered pinned tabs
        savePinnedTabOrder()
    }

    func navigate(to urlString: String) {
        guard let tab = selectedTab else { return }
        let url: URL?

        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            url = URL(string: urlString)
        } else if urlString.contains(".") && !urlString.contains(" ") {
            url = URL(string: "https://\(urlString)")
        } else {
            let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
            url = URL(string: "\(SettingsStore.shared.searchEngine.searchURL)\(encoded)")
        }

        if let url {
            tab.url = url
            tab.webView.load(URLRequest(url: url))
        }
    }
}
