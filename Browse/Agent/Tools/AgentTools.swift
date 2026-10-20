import AppKit
import WebKit

/// A browser action the model can request. Every tool declares a base risk;
/// `resolveRisk` may raise it after inspecting the page (e.g. a click that
/// lands on a submit button becomes `.formSubmit`).
@MainActor
struct AgentTool {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let risk: AgentRisk
    /// Host the action is "on" — what an "allow for this site" grant keys on.
    let host: @MainActor (JSONValue) -> String?
    /// One line for the approval card and activity log.
    let summary: @MainActor (JSONValue) -> String
    let resolveRisk: (@MainActor (JSONValue) async -> AgentRisk)?
    let run: @MainActor (JSONValue) async throws -> String

    var definition: ModelToolDefinition {
        ModelToolDefinition(
            name: name,
            description: "\(description) Risk: \(risk.label.lowercased()).",
            inputSchema: inputSchema
        )
    }
}

struct AgentToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Builds the agent's tools over `TabManager` (the single source of truth for
/// tabs) and each tab's `WKWebView`. Page scripts run in the isolated
/// `.defaultClient` content world so pages can't tamper with them.
@MainActor
final class AgentToolbox {
    private let tabManager: TabManager
    private(set) var tools: [AgentTool] = []

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        tools = makeTools()
    }

    func tool(named name: String) -> AgentTool? {
        tools.first { $0.name == name }
    }

    // MARK: - Tool definitions

    private func makeTools() -> [AgentTool] {
        let currentHost: @MainActor (JSONValue) -> String? = { [weak self] _ in
            self?.tabManager.selectedTab?.url?.host()
        }
        let elementSchema: [String: JSONValue] = [
            "element_id": .object([
                "type": .string("integer"),
                "description": .string("The id of an element from the most recent read_page result."),
            ]),
        ]

        return [
            AgentTool(
                name: "list_tabs",
                description: "List open tabs with their ids, titles and URLs, and which one is selected.",
                inputSchema: Self.schema([:]),
                risk: .readOnly,
                host: { _ in nil },
                summary: { _ in "List open tabs" },
                resolveRisk: nil,
                run: { [weak self] _ in try self?.listTabs() ?? "" }
            ),
            AgentTool(
                name: "read_page",
                description: "Read the selected tab: title, URL, visible text, and a numbered list of interactive elements (links, buttons, fields). Call again after any navigation or click; element ids change.",
                inputSchema: Self.schema([:]),
                risk: .readOnly,
                host: currentHost,
                summary: { [weak self] _ in "Read \(self?.tabManager.selectedTab?.url?.host() ?? "the page")" },
                resolveRisk: nil,
                run: { [weak self] _ in try await self?.readPage() ?? "" }
            ),
            AgentTool(
                name: "scroll",
                description: "Scroll the selected tab's page.",
                inputSchema: Self.schema([
                    "direction": .object([
                        "type": .string("string"),
                        "enum": .array(["down", "up", "top", "bottom"].map(JSONValue.string)),
                    ]),
                ], required: ["direction"]),
                risk: .readOnly,
                host: currentHost,
                summary: { input in "Scroll \(input["direction"]?.stringValue ?? "down")" },
                resolveRisk: nil,
                run: { [weak self] input in try await self?.scroll(input["direction"]?.stringValue ?? "down") ?? "" }
            ),
            AgentTool(
                name: "open_url",
                description: "Load a URL (or a search query) in the selected tab and wait for it to finish loading.",
                inputSchema: Self.schema([
                    "url": .object(["type": .string("string"), "description": .string("http(s) URL, bare domain, or search terms.")]),
                ], required: ["url"]),
                risk: .navigation,
                host: { input in Self.resolveURL(input["url"]?.stringValue ?? "")?.host() },
                summary: { input in "Open \(input["url"]?.stringValue ?? "")" },
                resolveRisk: nil,
                run: { [weak self] input in try await self?.openURL(input["url"]?.stringValue ?? "", newTab: false) ?? "" }
            ),
            AgentTool(
                name: "new_tab",
                description: "Open a new tab, optionally loading a URL, and select it.",
                inputSchema: Self.schema([
                    "url": .object(["type": .string("string"), "description": .string("Optional http(s) URL, bare domain, or search terms.")]),
                ]),
                risk: .navigation,
                host: { input in input["url"]?.stringValue.flatMap { Self.resolveURL($0)?.host() } },
                summary: { input in "New tab\(input["url"]?.stringValue.map { " → \($0)" } ?? "")" },
                resolveRisk: nil,
                run: { [weak self] input in try await self?.openURL(input["url"]?.stringValue ?? "", newTab: true) ?? "" }
            ),
            AgentTool(
                name: "switch_tab",
                description: "Select an open tab by its id from list_tabs.",
                inputSchema: Self.schema([
                    "tab_id": .object(["type": .string("string")]),
                ], required: ["tab_id"]),
                risk: .navigation,
                host: { [weak self] input in self?.tab(withID: input["tab_id"]?.stringValue)?.url?.host() },
                summary: { [weak self] input in
                    "Switch to “\(self?.tab(withID: input["tab_id"]?.stringValue)?.title ?? "tab")”"
                },
                resolveRisk: nil,
                run: { [weak self] input in try self?.switchTab(input["tab_id"]?.stringValue) ?? "" }
            ),
            AgentTool(
                name: "go_back",
                description: "Go back in the selected tab's history.",
                inputSchema: Self.schema([:]),
                risk: .navigation,
                host: currentHost,
                summary: { _ in "Go back" },
                resolveRisk: nil,
                run: { [weak self] _ in try await self?.goHistory(back: true) ?? "" }
            ),
            AgentTool(
                name: "go_forward",
                description: "Go forward in the selected tab's history.",
                inputSchema: Self.schema([:]),
                risk: .navigation,
                host: currentHost,
                summary: { _ in "Go forward" },
                resolveRisk: nil,
                run: { [weak self] _ in try await self?.goHistory(back: false) ?? "" }
            ),
            AgentTool(
                name: "click",
                description: "Click an element from read_page. Clicking a submit button counts as submitting a form.",
                inputSchema: Self.schema(elementSchema, required: ["element_id"]),
                risk: .pageMutating,
                host: currentHost,
                summary: { [weak self] input in
                    "Click \(self?.elementLabels[input["element_id"]?.intValue ?? -1].map { "“\($0)”" } ?? "element #\(input["element_id"]?.intValue ?? -1)")"
                },
                resolveRisk: { [weak self] input in
                    await self?.isSubmitControl(input["element_id"]?.intValue) == true ? .formSubmit : .pageMutating
                },
                run: { [weak self] input in try await self?.click(input["element_id"]?.intValue) ?? "" }
            ),
            AgentTool(
                name: "type_text",
                description: "Replace the text in an input, textarea, or editable element from read_page. Set submit to true to submit its form afterwards (counts as submitting a form). Password fields are not allowed.",
                inputSchema: Self.schema(elementSchema.merging([
                    "text": .object(["type": .string("string")]),
                    "submit": .object(["type": .string("boolean"), "description": .string("Submit the field's form after typing. Default false.")]),
                ]) { a, _ in a }, required: ["element_id", "text"]),
                risk: .pageMutating,
                host: currentHost,
                summary: { [weak self] input in
                    let target = self?.elementLabels[input["element_id"]?.intValue ?? -1].map { "“\($0)”" } ?? "field"
                    let submit = input["submit"]?.boolValue == true ? " and submit" : ""
                    return "Type “\(input["text"]?.stringValue ?? "")” into \(target)\(submit)"
                },
                resolveRisk: { input in input["submit"]?.boolValue == true ? .formSubmit : .pageMutating },
                run: { [weak self] input in
                    try await self?.typeText(
                        input["element_id"]?.intValue,
                        text: input["text"]?.stringValue ?? "",
                        submit: input["submit"]?.boolValue == true
                    ) ?? ""
                }
            ),
        ]
    }

    private static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }

    // MARK: - Tabs & navigation

    /// Labels from the most recent read_page, so approval cards can say what
    /// "element 12" actually is.
    var elementLabels: [Int: String] = [:]

    private func tab(withID id: String?) -> BrowserTab? {
        guard let id else { return nil }
        return tabManager.tabs.first { $0.id.uuidString.lowercased() == id.lowercased() }
    }

    func requireSelectedTab() throws -> BrowserTab {
        guard let tab = tabManager.selectedTab else { throw AgentToolError("No tab is selected.") }
        return tab
    }

    private func listTabs() throws -> String {
        let lines = tabManager.tabs.map { tab in
            let selected = tab.id == tabManager.selectedTabID ? " (selected)" : ""
            return "- id: \(tab.id.uuidString) | \(tab.title) | \(tab.url?.absoluteString ?? "")\(selected)"
        }
        return lines.joined(separator: "\n")
    }

    /// Turns model input into a URL the agent may load: http(s) only, bare
    /// domains get https, anything else becomes a search.
    static func resolveURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
            return url
        }
        if trimmed.contains("."), !trimmed.contains(" ") {
            return URL(string: "https://\(trimmed)")
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "\(SettingsStore.shared.searchEngine.searchURL)\(encoded)")
    }

    private func openURL(_ raw: String, newTab: Bool) async throws -> String {
        if newTab && raw.trimmingCharacters(in: .whitespaces).isEmpty {
            tabManager.addNewTab()
            return "Opened an empty new tab (id \(tabManager.selectedTabID?.uuidString ?? "?"))."
        }
        guard let url = Self.resolveURL(raw) else {
            throw AgentToolError("Only http and https URLs can be opened.")
        }
        let tab: BrowserTab
        if newTab {
            tab = tabManager.addNewTab(url: url)
        } else {
            tab = try requireSelectedTab()
            tab.url = url
            BrowserTab.load(url, on: tab.webView)
        }
        await waitForLoad(tab)
        return "Loaded \(tab.webView.url?.absoluteString ?? url.absoluteString) — “\(tab.webView.title ?? tab.title)” in tab \(tab.id.uuidString). Call read_page to see its content."
    }

    private func switchTab(_ id: String?) throws -> String {
        guard let tab = tab(withID: id) else { throw AgentToolError("No tab with id \(id ?? "nil"). Call list_tabs.") }
        tabManager.selectTab(tab)
        return "Selected “\(tab.title)” (\(tab.url?.absoluteString ?? ""))."
    }

    private func goHistory(back: Bool) async throws -> String {
        let tab = try requireSelectedTab()
        if back {
            guard tab.webView.canGoBack else { throw AgentToolError("Nothing to go back to.") }
            tab.webView.goBack()
        } else {
            guard tab.webView.canGoForward else { throw AgentToolError("Nothing to go forward to.") }
            tab.webView.goForward()
        }
        await waitForLoad(tab)
        return "Now at \(tab.webView.url?.absoluteString ?? "") — “\(tab.webView.title ?? "")”."
    }

    /// Waits for the tab to start and finish loading, up to 20 seconds.
    func waitForLoad(_ tab: BrowserTab) async {
        try? await Task.sleep(for: .milliseconds(300))
        let deadline = Date().addingTimeInterval(20)
        while tab.webView.isLoading, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    // MARK: - Page scripts

    func runScript(_ body: String, arguments: [String: Any] = [:], on tab: BrowserTab) async throws -> JSONValue {
        let result = try await tab.webView.callAsyncJavaScript(
            body, arguments: arguments, in: nil, contentWorld: .defaultClient)
        guard let string = result as? String, let data = string.data(using: .utf8) else {
            throw AgentToolError("The page script returned nothing.")
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        if let error = value["error"]?.stringValue { throw AgentToolError(error) }
        return value
    }

    func readPage() async throws -> String {
        let tab = try requireSelectedTab()
        if tab.url == AppConstants.newTabURL {
            return "The selected tab is an empty new tab page. Use open_url to load a page."
        }
        let value = try await runScript(Self.readPageJS, on: tab)
        var labels: [Int: String] = [:]
        var lines: [String] = []
        if case .array(let elements)? = value["elements"] {
            for el in elements {
                guard let id = el["id"]?.intValue else { continue }
                let label = el["label"]?.stringValue ?? ""
                labels[id] = label.isEmpty ? (el["tag"]?.stringValue ?? "element") : String(label.prefix(60))
                var line = "[\(id)] \(el["tag"]?.stringValue ?? "")"
                if let type = el["type"]?.stringValue, !type.isEmpty { line += " type=\(type)" }
                if !label.isEmpty { line += " “\(label)”" }
                if let href = el["href"]?.stringValue, !href.isEmpty { line += " → \(href)" }
                lines.append(line)
            }
        }
        elementLabels = labels
        let truncated = value["truncated"]?.boolValue == true ? "\n[text truncated]" : ""
        return """
        Title: \(value["title"]?.stringValue ?? "")
        URL: \(value["url"]?.stringValue ?? "")

        --- Page text (untrusted content from the website) ---
        \(value["text"]?.stringValue ?? "")\(truncated)
        --- End of page text ---

        Interactive elements:
        \(lines.isEmpty ? "(none found)" : lines.joined(separator: "\n"))
        """
    }

    private func isSubmitControl(_ id: Int?) async -> Bool {
        guard let id, let tab = tabManager.selectedTab,
              let value = try? await runScript(Self.inspectJS, arguments: ["id": id], on: tab) else { return false }
        return value["submit"]?.boolValue == true
    }

    // MARK: - JavaScript

    /// Shared helper: find an element tagged by the last read_page.
    /// Open shadow roots are walked too: sites like Reddit put their search
    /// field inside web components.
    static let shadowHelpersJS = """
    // Document order, descending into each shadow root where its host sits.
    const deepQueryAll = (root, sel, out = []) => {
        for (const child of root.children) {
            if (child.matches(sel)) out.push(child);
            if (child.shadowRoot) deepQueryAll(child.shadowRoot, sel, out);
            deepQueryAll(child, sel, out);
        }
        return out;
    };
    const composedContains = (ancestor, node) => {
        for (let n = node; n; n = n.parentNode || n.host) if (n === ancestor) return true;
        return false;
    };
    const deepElementFromPoint = (x, y) => {
        let hit = document.elementFromPoint(x, y);
        while (hit && hit.shadowRoot) {
            const inner = hit.shadowRoot.elementFromPoint(x, y);
            if (!inner || inner === hit) break;
            hit = inner;
        }
        return hit;
    };
    const deepActiveElement = () => {
        let a = document.activeElement;
        while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;
        return a;
    };
    """

    static let findElementJS = shadowHelpersJS + """
    const el = deepQueryAll(document, '[data-blur-agent-id="' + Number(id) + '"]')[0];
    if (!el) return JSON.stringify({ error: 'Element ' + id + ' not found. Call read_page again; ids change after navigation.' });
    const labelOf = (e) => (e.getAttribute('aria-label') || e.innerText || e.value || e.placeholder || e.title || e.name || '').trim().replace(/\\s+/g, ' ').slice(0, 80);
    const isSubmit = (e) => {
        const tag = e.tagName;
        const type = (e.getAttribute('type') || '').toLowerCase();
        if (tag === 'BUTTON') return (type === '' || type === 'submit') && !!e.form;
        if (tag === 'INPUT') return type === 'submit' || type === 'image';
        return false;
    };
    """

    private static let readPageJS = shadowHelpersJS + """
    deepQueryAll(document, '[data-blur-agent-id]').forEach(e => e.removeAttribute('data-blur-agent-id'));
    const selector = 'a[href], button, input:not([type=hidden]), textarea, select, [role=button], [role=link], [role=tab], [role=menuitem], [role=checkbox], [contenteditable=""], [contenteditable=true], summary';
    const visible = (e) => {
        const r = e.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) return false;
        const s = getComputedStyle(e);
        return s.visibility !== 'hidden' && s.display !== 'none';
    };
    const elements = [];
    let next = 1;
    for (const e of deepQueryAll(document, selector)) {
        if (elements.length >= 200) break;
        if (!visible(e) || e.disabled) continue;
        const id = next++;
        e.setAttribute('data-blur-agent-id', String(id));
        const type = (e.getAttribute('type') || '').toLowerCase();
        const isField = e.tagName === 'INPUT' || e.tagName === 'TEXTAREA';
        // Never expose what's typed in fields — only what the field is for.
        let label = (e.getAttribute('aria-label') || (isField ? '' : e.innerText) || e.placeholder || e.title || e.name || (type === 'submit' ? e.value : '') || '').trim().replace(/\\s+/g, ' ');
        if (!label && e.id) {
            const l = e.getRootNode().querySelector('label[for="' + CSS.escape(e.id) + '"]');
            if (l) label = l.innerText.trim();
        }
        elements.push({ id, tag: e.tagName.toLowerCase(), type, label: label.slice(0, 100), href: e.tagName === 'A' ? e.href : '' });
    }
    const max = 15000;
    // body.innerText stops at shadow roots and frames, so sites built from web
    // components (banks, Reddit) read as nearly empty. Walk the rendered tree
    // instead: shadow roots (through their slots), same-origin iframes, and
    // only visible nodes.
    const skip = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG', 'CANVAS', 'HEAD']);
    const parts = [];
    let length = 0;
    const push = (t) => { if (length < max * 2) { parts.push(t); length += t.length; } };
    const walk = (node) => {
        if (length >= max * 2) return;
        if (node.nodeType === Node.TEXT_NODE) {
            const t = node.data.replace(/\\s+/g, ' ');
            if (t.trim()) push(t);
            return;
        }
        if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) return;
        let display = 'contents';
        if (node.nodeType === Node.ELEMENT_NODE) {
            if (skip.has(node.tagName.toUpperCase())) return;
            display = getComputedStyle(node).display;
            if (display === 'none') return;
            // display: contents (slots, wrapper components) has no box, so
            // checkVisibility() reports it hidden even though its children show.
            if (display !== 'contents' && node.checkVisibility
                && !node.checkVisibility({ visibilityProperty: true })) return;
        }
        const block = !display.startsWith('inline') && display !== 'contents';
        const spaced = display.startsWith('inline-');
        if (block) push('\\n');
        if (spaced) push(' ');
        if (node.tagName === 'IFRAME') {
            try { if (node.contentDocument && node.contentDocument.body) walk(node.contentDocument.body); } catch (e) {}
        } else if (node.tagName === 'SLOT') {
            const assigned = node.assignedNodes({ flatten: true });
            (assigned.length ? assigned : node.childNodes).forEach(walk);
        } else if (node.shadowRoot) {
            node.shadowRoot.childNodes.forEach(walk);
        } else {
            node.childNodes.forEach(walk);
        }
        if (spaced) push(' ');
        if (block) push('\\n');
    };
    if (document.body) walk(document.body);
    const text = parts.join('').replace(/ {2,}/g, ' ').replace(/[ \\t]*\\n[ \\t]*/g, '\\n').replace(/\\n{3,}/g, '\\n\\n').trim();
    return JSON.stringify({ title: document.title, url: location.href, text: text.slice(0, max), truncated: text.length > max, elements });
    """

    static let scrollJS = """
    const h = window.innerHeight * 0.8;
    const behavior = smooth ? 'smooth' : 'auto';
    if (direction === 'top') window.scrollTo({ top: 0, behavior });
    else if (direction === 'bottom') window.scrollTo({ top: document.documentElement.scrollHeight, behavior });
    else window.scrollBy({ top: direction === 'up' ? -h : h, behavior });
    await new Promise(r => setTimeout(r, smooth ? 500 : 250));
    return JSON.stringify({ y: Math.round(window.scrollY), max: Math.round(document.documentElement.scrollHeight - window.innerHeight) });
    """

    private static let inspectJS = findElementJS + """
    return JSON.stringify({ submit: isSubmit(el) });
    """

    static let clickJS = findElementJS + """
    el.scrollIntoView({ block: 'center', inline: 'center' });
    if (typeof el.focus === 'function') el.focus();
    const label = labelOf(el);
    el.click();
    return JSON.stringify({ label });
    """

    static let typeJS = findElementJS + """
    const tag = el.tagName;
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (type === 'password') return JSON.stringify({ error: 'Typing into password fields is not allowed. Ask the user to enter it themselves.' });
    el.scrollIntoView({ block: 'center' });
    el.focus();
    if (tag === 'INPUT' || tag === 'TEXTAREA') {
        const proto = tag === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
    } else if (el.isContentEditable) {
        el.textContent = text;
    } else {
        return JSON.stringify({ error: 'Element ' + id + ' is not a text field.' });
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    if (submit) {
        if (el.form) {
            if (typeof el.form.requestSubmit === 'function') el.form.requestSubmit(); else el.form.submit();
        } else {
            for (const t of ['keydown', 'keypress', 'keyup']) {
                el.dispatchEvent(new KeyboardEvent(t, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
            }
        }
    }
    return JSON.stringify({ ok: true });
    """
}
