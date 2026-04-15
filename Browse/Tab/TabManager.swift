import AppKit
import Observation

@Observable
@MainActor
final class TabManager {
    var tabs: [BrowserTab] = []
    var selectedTabID: UUID?

    var selectedTab: BrowserTab? {
        guard let id = selectedTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var selectedIndex: Int? {
        guard let id = selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    init() {
        addNewTab(url: URL(string: SettingsStore.shared.homepageURL))
    }

    @discardableResult
    func addNewTab(url: URL? = nil, afterCurrent: Bool = true) -> BrowserTab {
        let tab = BrowserTab(url: url)
        if afterCurrent, let idx = selectedIndex {
            tabs.insert(tab, at: idx + 1)
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
        return tab
    }

    func closeTab(_ tab: BrowserTab) {
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
        tabs.removeAll { $0.id != tab.id }
        selectedTabID = tab.id
    }

    @discardableResult
    func duplicateTab(_ tab: BrowserTab) -> BrowserTab {
        addNewTab(url: tab.url)
    }

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
