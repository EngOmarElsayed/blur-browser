import AppKit
import WebKit

// MARK: - Settings

enum AgentActionSpeed: String, CaseIterable, Sendable {
    case slow, normal, fast

    var label: String {
        switch self {
        case .slow: "Slow"
        case .normal: "Normal"
        case .fast: "Fast"
        }
    }

    /// Multiplier on cursor travel time and typing delays.
    var factor: Double {
        switch self {
        case .slow: 1.7
        case .normal: 1
        case .fast: 0.45
        }
    }
}

/// Settings → AI: whether the agent's clicks and typing are animated with
/// the virtual cursor, and how fast.
enum AgentActionSettings {
    static let animateKey = "ai.animateActions"
    static let speedKey = "ai.actionSpeed"

    static var animate: Bool {
        get { UserDefaults.standard.object(forKey: animateKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: animateKey) }
    }

    static var speed: AgentActionSpeed {
        get { UserDefaults.standard.string(forKey: speedKey).flatMap(AgentActionSpeed.init) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: speedKey) }
    }
}

// MARK: - Driver

/// Shows and delivers one agent action on a `WKWebView`: moves the virtual
/// cursor, and sends real (trusted) mouse and key events straight to the web
/// view, the same way AppKit would for the user. The system cursor and the
/// window's event queue are never touched, so nothing leaks outside the page.
@MainActor
struct AgentInputDriver {
    let webView: WKWebView
    let overlay: AgentActionOverlay?
    let animate: Bool
    let speed: Double

    init(webView: WKWebView) {
        self.webView = webView
        self.animate = AgentActionSettings.animate
        self.speed = AgentActionSettings.speed.factor
        var responder = webView.nextResponder
        var host: AgentActionHosting?
        while let current = responder, host == nil {
            host = current as? AgentActionHosting
            responder = current.nextResponder
        }
        self.overlay = host?.agentActionOverlay()
    }

    // MARK: Session

    func begin(status: String) {
        overlay?.begin(status: status, showCursor: animate)
    }

    func setStatus(_ status: String) {
        overlay?.setStatus(status)
    }

    func end() {
        overlay?.end()
    }

    // MARK: Geometry

    /// Converts a CSS viewport point (`clientX/Y`) to web view coordinates.
    /// The ratio of view width to `innerWidth` covers page zoom and
    /// magnification.
    func webViewPoint(cssX: Double, cssY: Double, viewportWidth: Double) -> NSPoint? {
        guard viewportWidth > 0, webView.bounds.width > 0 else { return nil }
        let scale = webView.bounds.width / viewportWidth
        let x = cssX * scale
        let y = cssY * scale
        let point = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
        return webView.bounds.contains(point) ? point : nil
    }

    // MARK: Cursor

    func moveCursor(to point: NSPoint) async {
        guard animate, let overlay else { return }
        let target = overlay.convert(point, from: webView)
        let distance = overlay.cursorPoint.map { hypot($0.x - target.x, $0.y - target.y) } ?? 300
        // 300–500 ms at normal speed, longer for longer trips.
        let duration = (0.3 + min(distance, 800) / 800 * 0.2) * speed
        await overlay.moveCursor(to: target, duration: duration)
    }

    func ripple() {
        if animate { overlay?.ripple() }
    }

    // MARK: Mouse

    /// A left click at `point` (web view coordinates): move, press, release.
    func click(at point: NSPoint) async {
        guard let window = webView.window else { return }
        let location = webView.convert(point, to: nil)
        if let moved = mouseEvent(.mouseMoved, at: location, in: window) { webView.mouseMoved(with: moved) }
        if let down = mouseEvent(.leftMouseDown, at: location, in: window) { webView.mouseDown(with: down) }
        try? await Task.sleep(for: .milliseconds(Int.random(in: 50...90)))
        if let up = mouseEvent(.leftMouseUp, at: location, in: window) { webView.mouseUp(with: up) }
    }

    private func mouseEvent(_ type: NSEvent.EventType, at location: NSPoint, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: type == .mouseMoved ? 0 : 1,
            pressure: type == .leftMouseDown ? 1 : 0)
    }

    // MARK: Keyboard

    /// Makes the web view the window's first responder so key events reach
    /// the focused element.
    func focusWebView() {
        if webView.window?.firstResponder !== webView {
            webView.window?.makeFirstResponder(webView)
        }
    }

    /// Types one character as keyDown + keyUp. Newlines become Return.
    func type(_ character: Character) {
        if character == "\n" || character == "\r" {
            pressReturn()
            return
        }
        let text = String(character)
        let lower = text.lowercased()
        let (code, shifted) = Self.keyCodes[text] ?? Self.keyCodes[lower].map { ($0.0, true) } ?? (0, false)
        send(characters: text, ignoringModifiers: shifted ? Self.unshifted[text] ?? lower : text,
             keyCode: code, flags: shifted ? .shift : [])
    }

    func pressReturn() {
        send(characters: "\r", ignoringModifiers: "\r", keyCode: 36, flags: [])
    }

    /// Delay between keystrokes: human-ish and a little irregular.
    func keystrokeDelay() -> Duration {
        guard animate else { return .milliseconds(8) }
        return .milliseconds(Int(Double.random(in: 45...120) * speed))
    }

    private func send(characters: String, ignoringModifiers: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let window = webView.window else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: ignoringModifiers,
                isARepeat: false,
                keyCode: keyCode) else { continue }
            if type == .keyDown { webView.keyDown(with: event) } else { webView.keyUp(with: event) }
        }
    }

    /// US ANSI virtual key codes. `true` = needs Shift.
    private static let keyCodes: [String: (UInt16, Bool)] = {
        var map: [String: (UInt16, Bool)] = [:]
        let plain: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19),
            ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28),
            ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("l", 37), ("j", 38),
            ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47),
            (" ", 49), ("`", 50), ("\t", 48),
        ]
        for (char, code) in plain { map[char] = (code, false) }
        for (shiftedChar, base) in unshifted { if let code = map[base]?.0 { map[shiftedChar] = (code, true) } }
        return map
    }()

    private static let unshifted: [String: String] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]
}
