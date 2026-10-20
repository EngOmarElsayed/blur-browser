import AppKit

/// click, type_text and scroll, delivered like a person would: the virtual
/// cursor travels to the element, and the web view gets real mouse and key
/// events (so pages see `isTrusted` input). Which element to act on still
/// comes from read_page's ids. When a real event can't reach the element
/// (it's covered, or inside a cross-origin iframe), or the page never saw it,
/// the action falls back to the scripted path.
///
/// Permission checks happen before `run` is called (AgentController), so
/// nothing here decides what's allowed.
extension AgentToolbox {

    func scroll(_ direction: String) async throws -> String {
        let tab = try requireSelectedTab()
        let driver = AgentInputDriver(webView: tab.webView)
        driver.begin(status: "Agent is scrolling…")
        defer { driver.end() }
        let bounds = tab.webView.bounds
        await driver.moveCursor(to: NSPoint(x: bounds.midX, y: bounds.midY))
        let value = try await runScript(
            Self.scrollJS, arguments: ["direction": direction, "smooth": driver.animate], on: tab)
        return "Scrolled \(direction). Now at \(value["y"]?.intValue ?? 0) of \(value["max"]?.intValue ?? 0)px."
    }

    func click(_ id: Int?) async throws -> String {
        guard let id else { throw AgentToolError("element_id is required.") }
        let tab = try requireSelectedTab()
        let webView = tab.webView
        let before = webView.url
        let driver = AgentInputDriver(webView: webView)
        driver.begin(status: "Agent is clicking…")
        defer { driver.end() }

        let target = try await runScript(Self.targetJS, arguments: ["id": id, "smooth": driver.animate, "mode": "click"], on: tab)
        let label = target["label"]?.stringValue ?? "element \(id)"
        let point = aimPoint(for: target, driver: driver)
        if let point { await driver.moveCursor(to: point) }

        var delivered = false
        if let point, target["reachable"]?.boolValue == true {
            driver.ripple()
            await driver.click(at: point)
            try? await Task.sleep(for: .milliseconds(150))
            delivered = await sawTrustedInput(tab: tab, before: before, key: "clicked")
        }
        if !delivered {
            _ = try await runScript(Self.clickJS, arguments: ["id": id], on: tab)
        }

        try? await Task.sleep(for: .milliseconds(400))
        if webView.isLoading || webView.url != before { await waitForLoad(tab) }
        let navigated = webView.url != before ? " Page is now \(webView.url?.absoluteString ?? "")." : ""
        return "Clicked \(label).\(navigated) Call read_page to see the result."
    }

    func typeText(_ id: Int?, text: String, submit: Bool) async throws -> String {
        guard let id else { throw AgentToolError("element_id is required.") }
        let tab = try requireSelectedTab()
        let webView = tab.webView
        let before = webView.url
        let driver = AgentInputDriver(webView: webView)
        driver.begin(status: "Agent is typing…")
        defer { driver.end() }

        // Refuses password fields and non-text elements before any input.
        let target = try await runScript(Self.targetJS, arguments: ["id": id, "smooth": driver.animate, "mode": "type"], on: tab)
        let multiline = target["multiline"]?.boolValue == true
        let point = aimPoint(for: target, driver: driver)
        if let point { await driver.moveCursor(to: point) }
        if let point, target["reachable"]?.boolValue == true {
            driver.ripple()
            await driver.click(at: point)
            try? await Task.sleep(for: .milliseconds(120))
        }

        // Focus the field, select its contents so typing replaces them, and
        // start counting trusted keystrokes that land in it.
        var typedForReal = false
        let prepared = try? await runScript(Self.prepareTypeJS, arguments: ["id": id], on: tab)
        if prepared?["focused"]?.boolValue == true {
            driver.focusWebView()
            typedForReal = true
            let characters = multiline ? Array(text) : Array(text.replacingOccurrences(of: "\n", with: " "))
            for character in characters {
                if Task.isCancelled { break }
                // Never type into anything but the target, and never into a
                // password field, even if the page moves focus mid-way.
                let check = try? await runScript(Self.stillFocusedJS, arguments: ["id": id], on: tab)
                guard check?["focused"]?.boolValue == true else {
                    typedForReal = false
                    break
                }
                driver.type(character)
                try? await Task.sleep(for: driver.keystrokeDelay())
            }
        }

        let result = typedForReal
            ? try? await runScript(Self.finishTypeJS, arguments: ["id": id, "text": text], on: tab)
            : nil
        let keysLanded = (result?["keys"]?.intValue ?? 0) > 0
        if !keysLanded {
            // Real keystrokes didn't reach the field: set it by script,
            // including the submit, as before.
            _ = try await runScript(Self.typeJS, arguments: ["id": id, "text": text, "submit": submit], on: tab)
        } else {
            if result?["matches"]?.boolValue != true {
                // Keys arrived but the text came out different (keyboard
                // layout, input method): correct the value by script.
                _ = try await runScript(Self.typeJS, arguments: ["id": id, "text": text, "submit": false], on: tab)
            }
            if submit {
                driver.setStatus("Agent is submitting…")
                driver.focusWebView()
                driver.pressReturn()
            }
        }

        if submit {
            try? await Task.sleep(for: .milliseconds(400))
            await waitForLoad(tab)
        }
        let navigated = webView.url != before ? " Page is now \(webView.url?.absoluteString ?? "")." : ""
        return "Typed into element \(id)\(submit ? " and submitted" : "").\(navigated)"
    }

    // MARK: - Helpers

    private func aimPoint(for target: JSONValue, driver: AgentInputDriver) -> NSPoint? {
        guard case .number(let x)? = target["x"], case .number(let y)? = target["y"],
              case .number(let width)? = target["viewportWidth"] else { return nil }
        return driver.webViewPoint(cssX: x, cssY: y, viewportWidth: width)
    }

    /// Whether the page saw our trusted click. A navigation counts as yes;
    /// so does a probe that's gone (the document was replaced).
    private func sawTrustedInput(tab: BrowserTab, before: URL?, key: String) async -> Bool {
        if tab.webView.url != before || tab.webView.isLoading { return true }
        guard let probe = try? await runScript(Self.probeResultJS, on: tab) else { return true }
        return probe[key]?.boolValue ?? true
    }

    // MARK: - JavaScript

    /// Scrolls the element into view and reports where to aim: the centre of
    /// its visible part, in CSS viewport coordinates, and whether a click
    /// there would land on it. Arms a probe that notes a trusted click on it.
    static let targetJS = findElementJS + """
    if (window.__blurAgentProbeCleanup) window.__blurAgentProbeCleanup();
    const tag = el.tagName;
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (mode === 'type') {
        if (type === 'password') return JSON.stringify({ error: 'Typing into password fields is not allowed. Ask the user to enter it themselves.' });
        if (!(tag === 'INPUT' || tag === 'TEXTAREA' || el.isContentEditable)) return JSON.stringify({ error: 'Element ' + id + ' is not a text field.' });
    }
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: smooth ? 'smooth' : 'auto' });
    await new Promise(r => setTimeout(r, smooth ? 450 : 60));
    const rect = el.getBoundingClientRect();
    const left = Math.max(rect.left, 0), right = Math.min(rect.right, innerWidth);
    const top = Math.max(rect.top, 0), bottom = Math.min(rect.bottom, innerHeight);
    const visible = right > left && bottom > top;
    const x = visible ? (left + right) / 2 : null;
    const y = visible ? (top + bottom) / 2 : null;
    const hit = visible ? deepElementFromPoint(x, y) : null;
    const reachable = !!hit && (composedContains(el, hit) || (hit.control && hit.control === el));
    const probe = { clicked: false };
    // composedPath() sees through shadow roots, where e.target is retargeted.
    const onClick = (e) => { if (e.isTrusted && e.composedPath().some(n => n === el || n === hit)) probe.clicked = true; };
    window.addEventListener('click', onClick, true);
    window.__blurAgentProbe = probe;
    window.__blurAgentProbeCleanup = () => { window.removeEventListener('click', onClick, true); window.__blurAgentProbe = null; window.__blurAgentProbeCleanup = null; };
    return JSON.stringify({ label: labelOf(el), x, y, viewportWidth: innerWidth, reachable, multiline: tag === 'TEXTAREA' || el.isContentEditable });
    """

    static let probeResultJS = """
    const p = window.__blurAgentProbe;
    if (window.__blurAgentProbeCleanup) window.__blurAgentProbeCleanup();
    return JSON.stringify({ clicked: p ? p.clicked : null });
    """

    /// Focuses the field, selects its contents (so typing replaces them) and
    /// counts trusted keydowns that land in it.
    static let prepareTypeJS = findElementJS + """
    if (window.__blurAgentProbeCleanup) window.__blurAgentProbeCleanup();
    if ((el.getAttribute('type') || '').toLowerCase() === 'password') return JSON.stringify({ focused: false });
    el.focus();
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
        try { el.select(); } catch (e) { el.setSelectionRange && el.setSelectionRange(0, el.value.length); }
    } else if (el.isContentEditable) {
        const range = document.createRange();
        range.selectNodeContents(el);
        const sel = getSelection(); sel.removeAllRanges(); sel.addRange(range);
    }
    const counter = { keys: 0 };
    const onKey = (e) => { if (e.isTrusted && e.composedPath().includes(el)) counter.keys++; };
    document.addEventListener('keydown', onKey, true);
    window.__blurAgentKeys = counter;
    window.__blurAgentKeysCleanup = () => { document.removeEventListener('keydown', onKey, true); window.__blurAgentKeys = null; };
    const active = deepActiveElement();
    return JSON.stringify({ focused: !!active && composedContains(el, active) });
    """

    static let stillFocusedJS = findElementJS + """
    const active = deepActiveElement();
    const isPassword = !!active && (active.getAttribute('type') || '').toLowerCase() === 'password';
    return JSON.stringify({ focused: !isPassword && !!active && composedContains(el, active) });
    """

    /// Reports how many keystrokes landed and whether the field now holds
    /// the intended text. Only a yes/no leaves the page, never the value.
    static let finishTypeJS = findElementJS + """
    const counter = window.__blurAgentKeys;
    if (window.__blurAgentKeysCleanup) window.__blurAgentKeysCleanup();
    const value = (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') ? el.value : el.innerText;
    const norm = (s) => String(s).replace(/\\s+/g, ' ').trim();
    const expected = el.tagName === 'INPUT' ? text.replace(/\\n/g, ' ') : text;
    return JSON.stringify({ keys: counter ? counter.keys : 0, matches: norm(value) === norm(expected) });
    """
}
