# Password Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> Companion design document: [`2026-04-27-password-manager-design.md`](./2026-04-27-password-manager-design.md). Read it first — every architectural decision is captured there.

**Goal:** Add a built-in password manager to Browse covering autofill UI, login/signup/change-password form detection, and a save-on-success prompt that integrates with the system Keychain (and therefore Apple's Passwords app + iCloud Keychain).

**Architecture:** Three layers — JS content script (`passwordManager.js`) injected into every same-origin frame for form detection and submission tracking; a native `PasswordManagerCoordinator` (`@MainActor @Observable`) that handles inbound messages, owns popover/overlay UI, and tracks per-tab pending-save state; plain Keychain-backed `PasswordStore` and `BlocklistStore` for storage. One coordinator instance per tab, owned by `WebViewController`. Stores live on `BrowserWindowController` and are passed in by initializer.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSPanel, NSHostingView, NSViewController), `WKWebView` + `WKUserContentController`, Keychain Services (`kSecClassInternetPassword`), `UserDefaults`, plain JavaScript (no bundler — single hand-written file).

---

## Ground rules for the implementer

1. **Follow [CLAUDE.md](../../CLAUDE.md) without exception.** Most relevant: `@Observable` not `ObservableObject`; `NSHostingView` always wrapped in a plain `NSView`, never set as `self.view`; no `NSToolbar`; manual frame-based layout; tokens from `Constants.swift` for colors, never hardcoded hex.
2. **No test target exists.** Verification is manual on real websites, listed at the end of every task.
3. **Adding new Swift files requires Xcode.** Per CLAUDE.md: "Add/remove files through Xcode's project navigator." After writing a new `.swift` file to disk, **open Xcode, drag the file from Finder into the `Browse` group in the navigator**, and confirm "Browse" target membership in the file inspector. The build won't see it otherwise.
4. **Commit after every task.** Commit messages prefixed `feat(passwords):` (or `fix(passwords):` etc).
5. **Run a clean build between tasks** that touch native code: `xcodebuild -project Blur-Browser.xcodeproj -scheme Browse -configuration Debug build` from repo root. JS-only changes don't require a rebuild but do require an app relaunch (the user script is loaded once at startup).
6. **YAGNI.** The non-goals in the design doc are non-goals. Don't speculatively add password generation, settings UI, biometric auth, etc.

---

## Phase 1 — Foundations & storage

No UI in this phase. Pure types and Keychain plumbing. After Phase 1 the app builds and runs identically; only new files exist.

### Task 1: `SiteIdentity` + `Credential`

**Files:**
- Create: `Browse/Passwords/SiteIdentity.swift`
- Create: `Browse/Passwords/Credential.swift`

**Step 1: Create `SiteIdentity.swift`**

```swift
import Foundation

/// Pure-function helper for normalizing URLs to a stable site key.
/// v1 implementation: naive last-two-labels eTLD+1.
/// FUTURE: replace with Public Suffix List lookup so foo.github.io != bar.github.io.
enum SiteIdentity {
    /// "https://mail.example.com/path" -> "example.com"
    /// Returns nil for IPs, localhost, and hosts with < 2 labels.
    static func site(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host == "localhost" { return nil }
        if isIPAddress(host) { return nil }
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return nil }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Same as site(for:) but enforces save-eligibility rules:
    /// returns nil for non-https URLs (we never save credentials over HTTP).
    static func key(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        return site(for: url)
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        if host.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 { return true }
        if host.withCString({ inet_pton(AF_INET6, $0, &sin6.sin6_addr) }) == 1 { return true }
        return false
    }
}
```

**Step 2: Create `Credential.swift`**

```swift
import Foundation

struct Credential: Hashable, Identifiable, Sendable {
    let id: UUID
    let site: String        // eTLD+1 from SiteIdentity
    let username: String
    let password: String
    let createdAt: Date
    let updatedAt: Date

    init(id: UUID = UUID(),
         site: String,
         username: String,
         password: String,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.site = site
        self.username = username
        self.password = password
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

**Step 3: Add files to Xcode project** (open Xcode, drag both files from Finder into `Browse` → `Passwords` group, ensure target membership = `Browse`). Create the `Passwords` group first if it doesn't exist (right-click `Browse` → New Group).

**Step 4: Verify**

```bash
xcodebuild -project Blur-Browser.xcodeproj -scheme Browse -configuration Debug build
```
Expected: Build succeeds.

**Step 5: Commit**
```bash
git add Browse/Passwords/SiteIdentity.swift Browse/Passwords/Credential.swift Blur-Browser.xcodeproj/project.pbxproj
git commit -m "feat(passwords): site identity helper and credential value type"
```

---

### Task 2: `BlocklistStore`

**Files:**
- Create: `Browse/Passwords/BlocklistStore.swift`

**Step 1: Implement**

```swift
import Foundation

/// Tracks sites the user has explicitly opted out of password saving via "Never for this site".
/// Backed by UserDefaults; site keys are eTLD+1 strings from SiteIdentity.
final class BlocklistStore {
    private let defaults: UserDefaults
    private let key = "BrowsePasswordBlocklist"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ site: String) -> Bool {
        let entries = defaults.stringArray(forKey: key) ?? []
        return entries.contains(site)
    }

    func add(_ site: String) {
        var entries = Set(defaults.stringArray(forKey: key) ?? [])
        entries.insert(site)
        defaults.set(Array(entries).sorted(), forKey: key)
    }

    func remove(_ site: String) {
        var entries = Set(defaults.stringArray(forKey: key) ?? [])
        entries.remove(site)
        defaults.set(Array(entries).sorted(), forKey: key)
    }
}
```

**Step 2: Add to Xcode project, build, commit.**

```bash
git add Browse/Passwords/BlocklistStore.swift Blur-Browser.xcodeproj/project.pbxproj
git commit -m "feat(passwords): user defaults blocklist store"
```

---

### Task 3: `PasswordStore` (Keychain)

**Files:**
- Create: `Browse/Passwords/PasswordStore.swift`

**Step 1: Implement**

The full Keychain attribute layout matches the design doc. Note `kSecAttrSynchronizable = true` so saved credentials sync via iCloud Keychain and appear in Apple Passwords app on the user's other devices.

```swift
import Foundation
import Security
import os

final class PasswordStore {
    private let log = Logger(subsystem: "com.browse.app", category: "PasswordStore")
    private let labelPrefix = "Browse — "

    func save(_ cred: Credential) {
        let item = baseAttributes(site: cred.site, username: cred.username)
            .merging([
                kSecValueData as String: Data(cred.password.utf8),
                kSecAttrLabel as String: labelPrefix + cred.site,
                kSecAttrGeneric as String: idMetadata(cred.id),
                kSecAttrSynchronizable as String: kCFBooleanTrue!,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]) { current, _ in current }

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Same site+username already exists; treat save as update.
            update(site: cred.site, username: cred.username, password: cred.password)
            return
        }
        if status != errSecSuccess {
            log.error("SecItemAdd failed: \(status, privacy: .public)")
        }
    }

    func update(id: UUID, password: String) {
        guard let cred = lookupAll().first(where: { $0.id == id }) else { return }
        update(site: cred.site, username: cred.username, password: password)
    }

    private func update(site: String, username: String, password: String) {
        let query = baseAttributes(site: site, username: username)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess {
            log.error("SecItemUpdate failed: \(status, privacy: .public)")
        }
    }

    func lookup(forSite site: String) -> [Credential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: site,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { credential(from: $0) }
    }

    func delete(id: UUID) {
        guard let cred = lookupAll().first(where: { $0.id == id }) else { return }
        let query = baseAttributes(site: cred.site, username: cred.username)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("SecItemDelete failed: \(status, privacy: .public)")
        }
    }

    // MARK: - Private

    private func baseAttributes(site: String, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: site,
            kSecAttrAccount as String: username,
        ]
    }

    private func lookupAll() -> [Credential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { credential(from: $0) }
    }

    private func credential(from item: [String: Any]) -> Credential? {
        guard
            let site = item[kSecAttrServer as String] as? String,
            let username = item[kSecAttrAccount as String] as? String,
            let data = item[kSecValueData as String] as? Data,
            let password = String(data: data, encoding: .utf8)
        else { return nil }

        let id = decodeId(from: item[kSecAttrGeneric as String] as? Data) ?? UUID()
        let createdAt = item[kSecAttrCreationDate as String] as? Date ?? .now
        let updatedAt = item[kSecAttrModificationDate as String] as? Date ?? createdAt

        // Filter out our own labelPrefix-less entries to avoid colliding with other apps' items
        // that happen to use kSecClassInternetPassword. We always write a Browse — prefix label.
        if let label = item[kSecAttrLabel as String] as? String, !label.hasPrefix(labelPrefix) {
            return nil
        }

        return Credential(id: id, site: site, username: username, password: password,
                          createdAt: createdAt, updatedAt: updatedAt)
    }

    private func idMetadata(_ id: UUID) -> Data {
        try! JSONSerialization.data(withJSONObject: ["id": id.uuidString])
    }

    private func decodeId(from data: Data?) -> UUID? {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let raw = obj["id"], let id = UUID(uuidString: raw) else { return nil }
        return id
    }
}
```

**Step 2: Confirm `Browse.entitlements`** has Keychain Sharing enabled. Open the file and check; if missing, add `keychain-access-groups` with the app's bundle id. (Without this, Keychain still works but iCloud sync may not.)

**Step 3: Add to Xcode project, build, commit.**

```bash
git add Browse/Passwords/PasswordStore.swift Browse/Resources/Browse.entitlements Blur-Browser.xcodeproj/project.pbxproj
git commit -m "feat(passwords): keychain-backed password store"
```

---

## Phase 2 — Bridge skeleton

After this phase, the app will inject the JS, log every message it receives, but do nothing else. Useful baseline before adding logic.

### Task 4: JS skeleton + WebViewConfiguration wiring + Coordinator skeleton

**Files:**
- Create: `Browse/Passwords/Resources/passwordManager.js`
- Create: `Browse/Passwords/PasswordManagerCoordinator.swift`
- Modify: `Browse/WebContent/WebViewConfiguration.swift`
- Modify: `Browse/WebContent/WebViewController.swift`
- Modify: `Browse/Window/BrowserWindowController.swift`

**Step 1: Create `Browse/Passwords/Resources/passwordManager.js`**

```javascript
(function () {
  'use strict';

  const post = (msg) => {
    try {
      window.webkit.messageHandlers.passwordManager.postMessage(msg);
    } catch (e) {
      // Channel not available (e.g., about:blank during early load); ignore.
    }
  };

  const namespace = {
    fillField: function (_payload) { /* implemented in Task 7 */ },
    fillCredential: function (_payload) { /* implemented in Task 7 */ },
    rescan: function () { /* implemented in Task 5 */ },
  };
  Object.defineProperty(window, '__BrowsePasswordManager', {
    value: namespace, writable: false, configurable: false,
  });

  post({ kind: 'scriptReady', site: location.hostname });
})();
```

**Step 2: Create `PasswordManagerCoordinator.swift`** (minimal — just receive and log).

```swift
import AppKit
import Observation
import WebKit
import os

@MainActor
@Observable
final class PasswordManagerCoordinator: NSObject {
    private let log = Logger(subsystem: "com.browse.app", category: "PasswordManager")
    private let passwordStore: PasswordStore
    private let blocklistStore: BlocklistStore
    weak var webView: WKWebView?

    init(passwordStore: PasswordStore, blocklistStore: BlocklistStore) {
        self.passwordStore = passwordStore
        self.blocklistStore = blocklistStore
        super.init()
    }
}

extension PasswordManagerCoordinator: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        // Decode happens here; for the skeleton we just log the raw body.
        let body = message.body
        Task { @MainActor in
            self.log.info("inbound: \(String(describing: body), privacy: .public)")
        }
    }
}
```

**Step 3: Wire into `WebViewConfiguration.swift`.** Find the function that builds the `WKWebViewConfiguration`. Add the user script and message handler. The user script source is loaded from the bundle at runtime:

```swift
// At the top of the file, near other helpers:
private func loadPasswordManagerScript() -> WKUserScript? {
    guard let url = Bundle.main.url(forResource: "passwordManager",
                                    withExtension: "js",
                                    subdirectory: nil),
          let source = try? String(contentsOf: url, encoding: .utf8) else {
        return nil
    }
    return WKUserScript(source: source,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: false)
}
```

Where the configuration is built, accept a `coordinator: PasswordManagerCoordinator` parameter (or have `WebViewController` install it after the webview is created — see step 4). The handler registration looks like:

```swift
configuration.userContentController.add(coordinator, name: "passwordManager")
if let script = loadPasswordManagerScript() {
    configuration.userContentController.addUserScript(script)
}
```

If `WebViewConfiguration` is a static factory and you don't want to thread the coordinator through, register the handler in `WebViewController` after creating the web view instead:

```swift
// In WebViewController, after webView is created:
webView.configuration.userContentController.add(coordinator, name: "passwordManager")
if let script = loadPasswordManagerScript() {
    webView.configuration.userContentController.addUserScript(script)
}
```

Pick whichever shape fits the existing code; the design doc allows either.

**Step 4: Wire `PasswordManagerCoordinator` into `WebViewController`.** Add a stored property:

```swift
private var passwordCoordinator: PasswordManagerCoordinator?
```

In the initializer (or wherever `WebViewController` is constructed), accept `passwordStore: PasswordStore, blocklistStore: BlocklistStore`. Construct the coordinator in `viewDidLoad` (or wherever the web view is set up), assign `coordinator.webView = self.webView`, and register the handler/script as in step 3.

**Step 5: Wire stores into `BrowserWindowController.swift`.** Add stored properties:

```swift
let passwordStore = PasswordStore()
let blocklistStore = BlocklistStore()
```

Pass them through to every `WebViewController` you instantiate.

**Step 6: Bundle the JS file.** In Xcode, ensure `passwordManager.js` is added to the `Browse` target's "Copy Bundle Resources" build phase. (Drag the file into the project navigator, then select the file → File Inspector → Target Membership → check `Browse`. Verify in target Build Phases that it appears under "Copy Bundle Resources".)

**Step 7: Manual verification**

1. Build and run.
2. Open any HTTPS site (e.g., `https://github.com`).
3. In the macOS Console app (or Xcode console), filter by subsystem `com.browse.app` category `PasswordManager`.
4. Expect to see one log line of the form `inbound: {kind = scriptReady; site = "github.com";}` per page load.
5. Reload the page — expect another `scriptReady` log.

If you don't see logs: check Console for `passwordManager` errors (channel not registered, script not loaded, etc.).

**Step 8: Commit**

```bash
git add Browse/Passwords Browse/WebContent/WebViewConfiguration.swift Browse/WebContent/WebViewController.swift Browse/Window/BrowserWindowController.swift Blur-Browser.xcodeproj/project.pbxproj
git commit -m "feat(passwords): inject content script and bridge skeleton"
```

---

## Phase 3 — Form detection

After this phase, the JS detects forms, classifies them, tracks focus and submissions, and reports a 3-second success window. Native still only logs.

### Task 5: `scan()` + classification + `formsDetected`

**Files:**
- Modify: `Browse/Passwords/Resources/passwordManager.js`

**Step 1: Replace the script with the scanning version.** Full file content below; preserves the `__BrowsePasswordManager` and `scriptReady` blocks from Task 4 and adds the scanner.

```javascript
(function () {
  'use strict';

  const post = (msg) => {
    try { window.webkit.messageHandlers.passwordManager.postMessage(msg); }
    catch (e) { /* channel not available */ }
  };

  const FIELD_ID_ATTR = 'data-bm-field-id';
  const UNIT_ID_ATTR  = 'data-bm-unit-id';

  const uuid = () => {
    if (crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'u-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  };

  const idFor = (el, attr) => {
    let id = el.getAttribute(attr);
    if (!id) { id = uuid(); el.setAttribute(attr, id); }
    return id;
  };

  // --- Form unit & field discovery ---

  const isVisible = (el) => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    return el.getClientRects().length > 0;
  };

  const findUnit = (passwordEl) => {
    const form = passwordEl.closest('form');
    if (form) return form;
    // Walk up until we find an ancestor with another input
    let node = passwordEl.parentElement;
    while (node && node !== document.body) {
      if (node.querySelectorAll('input').length >= 2) return node;
      node = node.parentElement;
    }
    return passwordEl.parentElement || document.body;
  };

  const findUsernameField = (unit, passwordEl) => {
    // Prefer autocomplete-marked field
    const tagged = unit.querySelector('input[autocomplete~="username"], input[autocomplete~="email"]');
    if (tagged) return tagged;

    // Otherwise nearest preceding text/email/tel input in DOM order
    const candidates = unit.querySelectorAll('input[type="text"], input[type="email"], input[type="tel"], input:not([type])');
    let best = null;
    for (const c of candidates) {
      if (c === passwordEl) break;
      // Compare DOM position
      if (c.compareDocumentPosition(passwordEl) & Node.DOCUMENT_POSITION_FOLLOWING) {
        best = c;
      }
    }
    return best;
  };

  const SIGNUP_RE  = /sign\s*up|register|create.*account|join/i;
  const CHANGE_RE  = /change|update.*password|new.*password|reset.*password/i;
  const LOGIN_RE   = /log\s*in|sign\s*in/i;

  const classify = (unit) => {
    const pwInputs = unit.querySelectorAll('input[type="password"]');
    const hasNew = !![...pwInputs].find((p) => /new-password/.test(p.getAttribute('autocomplete') || ''));
    const hasCurrent = !![...pwInputs].find((p) => /current-password/.test(p.getAttribute('autocomplete') || ''));
    if (hasNew && hasCurrent) return 'change_password';
    if (hasNew) return 'signup';
    if (pwInputs.length >= 2) return 'signup';

    // Heuristics on submit-button text + form id/class
    const text = (unit.textContent || '').slice(0, 1000);
    const idClass = (unit.id || '') + ' ' + (unit.className || '');
    if (CHANGE_RE.test(text) || CHANGE_RE.test(idClass)) return 'change_password';
    if (SIGNUP_RE.test(text) || SIGNUP_RE.test(idClass)) return 'signup';
    return 'login';
  };

  // Iframe-aware rect: walks up parent windows accumulating offsets so the
  // returned rect is in the TOP document's coordinate space.
  const rectInTopDoc = (el) => {
    const r = el.getBoundingClientRect();
    let x = r.left, y = r.top;
    let win = window;
    while (win !== window.top) {
      try {
        const fe = win.frameElement;
        if (!fe) break;
        const fr = fe.getBoundingClientRect();
        x += fr.left;
        y += fr.top;
        win = win.parent;
      } catch (e) { break; }
    }
    return { x, y, w: r.width, h: r.height };
  };

  const detected = new Map(); // unitId -> { unit, classification, usernameField, passwordField }

  const scan = () => {
    detected.clear();
    const passwords = document.querySelectorAll('input[type="password"]');
    const forms = [];

    for (const pw of passwords) {
      if (!isVisible(pw)) continue;
      const unit = findUnit(pw);
      const unitId = idFor(unit, UNIT_ID_ATTR);
      const username = findUsernameField(unit, pw);
      const classification = classify(unit);
      const fieldId = idFor(pw, FIELD_ID_ATTR);
      const usernameId = username ? idFor(username, FIELD_ID_ATTR) : null;

      detected.set(unitId, { unit, classification, usernameField: username, passwordField: pw });

      forms.push({
        unitId, classification,
        usernameFieldId: usernameId,
        passwordFieldId: fieldId,
        usernameRect: username ? rectInTopDoc(username) : null,
        passwordRect: rectInTopDoc(pw),
      });
    }

    post({ kind: 'formsDetected', site: location.hostname, forms });
  };

  let scanTimer = null;
  const scheduleScan = () => {
    if (scanTimer) clearTimeout(scanTimer);
    scanTimer = setTimeout(scan, 150);
  };

  // Re-scan on DOM mutations (debounced)
  const mo = new MutationObserver(scheduleScan);
  mo.observe(document.documentElement, {
    subtree: true, childList: true,
    attributes: true, attributeFilter: ['type', 'autocomplete'],
  });

  // --- Public API ---

  const namespace = {
    fillField: function (_payload) { /* Task 7 */ },
    fillCredential: function (_payload) { /* Task 7 */ },
    rescan: scan,
  };
  Object.defineProperty(window, '__BrowsePasswordManager', {
    value: namespace, writable: false, configurable: false,
  });

  // Initial run
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan, { once: true });
  } else {
    scan();
  }
  post({ kind: 'scriptReady', site: location.hostname });
})();
```

**Step 2: Manual verification**

1. Build, run, open `https://github.com/login`.
2. Console should now log a `formsDetected` message with one form, classification `login`, both `usernameRect` and `passwordRect` populated.
3. Open `https://github.com/signup`. Expect a `formsDetected` with classification `signup`.
4. Open a SPA-style site like `https://app.linear.app/`. Expect `formsDetected` (possibly delayed by ~150ms after the React tree renders).

**Step 3: Commit**
```bash
git add Browse/Passwords/Resources/passwordManager.js
git commit -m "feat(passwords): scan and classify login/signup/change-password forms"
```

---

### Task 6: Focus / blur / viewport tracking

**Files:**
- Modify: `Browse/Passwords/Resources/passwordManager.js`

**Step 1: Add focus/blur/scroll listeners.** Insert after the `MutationObserver` block:

```javascript
// --- Focus / blur / viewport tracking ---

const fieldInfo = (el) => {
  const fieldId = el.getAttribute(FIELD_ID_ATTR);
  if (!fieldId) return null;
  for (const [unitId, rec] of detected) {
    if (rec.passwordField === el) return { unitId, fieldId, role: 'password' };
    if (rec.usernameField === el) return { unitId, fieldId, role: 'username' };
  }
  return null;
};

document.addEventListener('focusin', (ev) => {
  const target = ev.target;
  if (!(target instanceof HTMLInputElement)) return;
  const info = fieldInfo(target);
  if (!info) return;
  post({
    kind: 'fieldFocused',
    unitId: info.unitId,
    fieldId: info.fieldId,
    role: info.role,
    rect: rectInTopDoc(target),
  });
}, true);

document.addEventListener('focusout', (ev) => {
  const target = ev.target;
  if (!(target instanceof HTMLInputElement)) return;
  const info = fieldInfo(target);
  if (!info) return;
  post({ kind: 'fieldBlurred', fieldId: info.fieldId });
}, true);

let viewportTimer = null;
const onViewportChange = () => {
  if (viewportTimer) return;
  viewportTimer = setTimeout(() => {
    viewportTimer = null;
    post({ kind: 'viewportChanged' });
  }, 50);
};
window.addEventListener('scroll', onViewportChange, true);
window.addEventListener('resize', onViewportChange);
```

**Step 2: Manual verification**

1. Build, run, open `https://github.com/login`.
2. Click into the username field. Console: `fieldFocused` with `role: "username"` and a populated rect.
3. Click into the password field. Console: `fieldFocused` with `role: "password"`.
4. Click outside the form. Console: `fieldBlurred`.
5. Scroll the page. Console: `viewportChanged` (debounced — at most one per ~50ms).

**Step 3: Commit**
```bash
git add Browse/Passwords/Resources/passwordManager.js
git commit -m "feat(passwords): track field focus, blur, and viewport changes"
```

---

### Task 7: Submission tracking + 3s success watcher + fill API

**Files:**
- Modify: `Browse/Passwords/Resources/passwordManager.js`

**Step 1: Patch `history.pushState` / `replaceState`.** At the top of the IIFE, after the early helpers:

```javascript
// Synthesize a CustomEvent for SPA navigations so the success watcher can detect them.
(function patchHistory() {
  const fire = () => window.dispatchEvent(new CustomEvent('__bm_locationChanged'));
  const orig = { push: history.pushState, replace: history.replaceState };
  history.pushState = function (...args) { const r = orig.push.apply(this, args); fire(); return r; };
  history.replaceState = function (...args) { const r = orig.replace.apply(this, args); fire(); return r; };
  window.addEventListener('popstate', fire);
})();
```

**Step 2: Add submission capture and success watcher.** Insert after the focus/blur block:

```javascript
// --- Submission tracking + success watcher ---

const SUBMIT_BUTTON_RE = /log\s*in|sign\s*in|continue|submit|sign\s*up|register|create.*account|update.*password|change.*password/i;

const isSubmitButton = (el, unit) => {
  if (!el) return false;
  if (el.tagName === 'BUTTON' && (el.type === 'submit' || !el.type)) return unit.contains(el);
  if (el.tagName === 'INPUT' && el.type === 'submit') return unit.contains(el);
  if (unit.contains(el) && (el.tagName === 'BUTTON' || el.getAttribute('role') === 'button')) {
    return SUBMIT_BUTTON_RE.test(el.textContent || '');
  }
  return false;
};

const captureSubmission = (rec) => {
  const username = rec.usernameField ? rec.usernameField.value : '';
  const password = rec.passwordField ? rec.passwordField.value : '';
  if (!password) return; // ignore empty submissions
  post({
    kind: 'formSubmitted',
    unitId: rec.unit.getAttribute(UNIT_ID_ATTR),
    classification: rec.classification,
    username, password,
  });
  watchForSuccess(rec);
};

document.addEventListener('submit', (ev) => {
  for (const rec of detected.values()) {
    if (rec.unit === ev.target || rec.unit.contains(ev.target)) {
      captureSubmission(rec);
      return;
    }
  }
}, true);

document.addEventListener('click', (ev) => {
  for (const rec of detected.values()) {
    if (isSubmitButton(ev.target, rec.unit)) {
      // Defer slightly so the form's own click handlers see current values first.
      setTimeout(() => captureSubmission(rec), 0);
      return;
    }
  }
}, true);

const watchForSuccess = (rec) => {
  const unitId = rec.unit.getAttribute(UNIT_ID_ATTR);
  const passwordEl = rec.passwordField;
  let resolved = false;

  const resolve = (kind) => {
    if (resolved) return;
    resolved = true;
    cleanup();
    post({ kind, unitId });
  };

  const onLocChange = () => resolve('loginLikelySucceeded');
  const onUnload   = () => resolve('loginLikelySucceeded');

  const checkPasswordGone = () => {
    if (!passwordEl.isConnected) return resolve('loginLikelySucceeded');
    const cs = getComputedStyle(passwordEl);
    if (cs.display === 'none' || cs.visibility === 'hidden') return resolve('loginLikelySucceeded');
    if (passwordEl.value === '' && document.activeElement !== passwordEl) {
      // Password cleared & unfocused — treat as cleared by the page after success.
      return resolve('loginLikelySucceeded');
    }
  };

  const tickInterval = setInterval(checkPasswordGone, 200);
  window.addEventListener('__bm_locationChanged', onLocChange);
  window.addEventListener('beforeunload', onUnload);

  const timeout = setTimeout(() => resolve('loginInconclusive'), 3000);

  function cleanup() {
    clearInterval(tickInterval);
    clearTimeout(timeout);
    window.removeEventListener('__bm_locationChanged', onLocChange);
    window.removeEventListener('beforeunload', onUnload);
  }
};
```

**Step 3: Implement `fillField` and `fillCredential`.** Replace the namespace assignment:

```javascript
const findFieldById = (id) => document.querySelector(`[${FIELD_ID_ATTR}="${id}"]`);

const fillElement = (el, value) => {
  if (!el) return;
  // Use the native value setter so React/Vue see the change.
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  setter.call(el, value);
  el.dispatchEvent(new Event('input',  { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
  el.dispatchEvent(new KeyboardEvent('keyup',   { bubbles: true }));
};

const namespace = {
  fillField: function ({ fieldId, value }) {
    fillElement(findFieldById(fieldId), value);
  },
  fillCredential: function ({ usernameFieldId, username, passwordFieldId, password }) {
    fillElement(findFieldById(usernameFieldId), username);
    fillElement(findFieldById(passwordFieldId), password);
  },
  rescan: scan,
};
Object.defineProperty(window, '__BrowsePasswordManager', {
  value: namespace, writable: false, configurable: false,
});
```

**Step 4: Manual verification**

1. Build, run, open `https://github.com/login`.
2. Type any username + an obviously-wrong password, click Sign in. Console: `formSubmitted` with the typed values, then within 3s `loginInconclusive` (login failed, password field still present).
3. Now type your real credentials and sign in. Console: `formSubmitted`, then within 3s `loginLikelySucceeded` (page navigated to your dashboard).
4. From the Safari Web Inspector's Console (Develop menu → web view → Show Web Inspector), run `__BrowsePasswordManager.fillCredential({usernameFieldId: '<id from logs>', username: 'foo', passwordFieldId: '<id>', password: 'bar'})` — verify both fields populate. (Use the field ids from the most recent `formsDetected` log.)

**Step 5: Commit**
```bash
git add Browse/Passwords/Resources/passwordManager.js
git commit -m "feat(passwords): submission tracking, success watcher, and fill API"
```

---

## Phase 4 — Save prompt

After this phase, the save / update prompt appears in the top-left of the web view after a successful login, with full Save / Never / × actions.

### Task 8: Native message decoding

**Files:**
- Create: `Browse/Passwords/InboundMessage.swift`
- Modify: `Browse/Passwords/PasswordManagerCoordinator.swift`

**Step 1: Create `InboundMessage.swift`** — type-safe enum decoded from the bridge.

```swift
import Foundation

enum FormClassification: String, Decodable {
    case login, signup, change_password
}

enum FieldRole: String, Decodable {
    case username, password
}

struct CGRectPayload: Decodable {
    let x: Double, y: Double, w: Double, h: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct DetectedForm: Decodable {
    let unitId: String
    let classification: FormClassification
    let usernameFieldId: String?
    let passwordFieldId: String
    let usernameRect: CGRectPayload?
    let passwordRect: CGRectPayload
}

enum InboundMessage: Decodable {
    case formsDetected(site: String, forms: [DetectedForm])
    case fieldFocused(unitId: String, fieldId: String, role: FieldRole, rect: CGRectPayload)
    case fieldBlurred(fieldId: String)
    case viewportChanged
    case formSubmitted(unitId: String, classification: FormClassification,
                       username: String, password: String)
    case loginLikelySucceeded(unitId: String)
    case loginInconclusive(unitId: String)
    case scriptReady(site: String)

    private enum Kind: String, Decodable {
        case formsDetected, fieldFocused, fieldBlurred, viewportChanged
        case formSubmitted, loginLikelySucceeded, loginInconclusive, scriptReady
    }

    private enum Keys: String, CodingKey {
        case kind, site, forms, unitId, fieldId, role, rect
        case classification, username, password
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .formsDetected:
            self = .formsDetected(site: try c.decode(String.self, forKey: .site),
                                  forms: try c.decode([DetectedForm].self, forKey: .forms))
        case .fieldFocused:
            self = .fieldFocused(unitId: try c.decode(String.self, forKey: .unitId),
                                 fieldId: try c.decode(String.self, forKey: .fieldId),
                                 role: try c.decode(FieldRole.self, forKey: .role),
                                 rect: try c.decode(CGRectPayload.self, forKey: .rect))
        case .fieldBlurred:
            self = .fieldBlurred(fieldId: try c.decode(String.self, forKey: .fieldId))
        case .viewportChanged:
            self = .viewportChanged
        case .formSubmitted:
            self = .formSubmitted(unitId: try c.decode(String.self, forKey: .unitId),
                                  classification: try c.decode(FormClassification.self, forKey: .classification),
                                  username: try c.decode(String.self, forKey: .username),
                                  password: try c.decode(String.self, forKey: .password))
        case .loginLikelySucceeded:
            self = .loginLikelySucceeded(unitId: try c.decode(String.self, forKey: .unitId))
        case .loginInconclusive:
            self = .loginInconclusive(unitId: try c.decode(String.self, forKey: .unitId))
        case .scriptReady:
            self = .scriptReady(site: try c.decode(String.self, forKey: .site))
        }
    }
}
```

**Step 2: Update `PasswordManagerCoordinator.swift`** to decode and dispatch:

```swift
@MainActor
@Observable
final class PasswordManagerCoordinator: NSObject {
    var pendingSaveCredential: PendingCredential?
    var autofillSuggestions: [Credential] = []
    var focusedFieldRect: CGRect?

    enum PendingCredential: Equatable {
        case save(site: String, username: String, password: String)
        case update(site: String, username: String, password: String, existingId: UUID)
    }

    private let log = Logger(subsystem: "com.browse.app", category: "PasswordManager")
    private let passwordStore: PasswordStore
    private let blocklistStore: BlocklistStore
    weak var webView: WKWebView?

    private var lastSubmissionByUnit: [String: (classification: FormClassification, username: String, password: String)] = [:]

    init(passwordStore: PasswordStore, blocklistStore: BlocklistStore) {
        self.passwordStore = passwordStore
        self.blocklistStore = blocklistStore
        super.init()
    }

    private func handle(_ msg: InboundMessage) {
        switch msg {
        case .scriptReady:
            lastSubmissionByUnit.removeAll()
        case .formsDetected:
            break // Used in autofill; logged for now.
        case .fieldFocused, .fieldBlurred, .viewportChanged:
            break // Used by the popover in Phase 5.
        case .formSubmitted(let unitId, let classification, let username, let password):
            lastSubmissionByUnit[unitId] = (classification, username, password)
        case .loginLikelySucceeded(let unitId):
            handleSuccess(unitId: unitId)
        case .loginInconclusive(let unitId):
            lastSubmissionByUnit.removeValue(forKey: unitId)
        }
    }

    private func handleSuccess(unitId: String) {
        guard let payload = lastSubmissionByUnit.removeValue(forKey: unitId) else { return }
        guard let url = webView?.url, let site = SiteIdentity.key(for: url) else { return }
        if blocklistStore.contains(site) { return }

        let existing = passwordStore.lookup(forSite: site)
        if let same = existing.first(where: { $0.username == payload.username && $0.password == payload.password }) {
            _ = same
            return // No-op: same username, same password — nothing to save or update.
        }
        if let match = existing.first(where: { $0.username == payload.username }) {
            pendingSaveCredential = .update(site: site,
                                            username: payload.username,
                                            password: payload.password,
                                            existingId: match.id)
        } else {
            pendingSaveCredential = .save(site: site,
                                          username: payload.username,
                                          password: payload.password)
        }
    }
}

extension PasswordManagerCoordinator: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        guard let msg = try? JSONDecoder().decode(InboundMessage.self, from: data) else {
            Task { @MainActor in self.log.warning("undecodable message: \(String(describing: body), privacy: .public)") }
            return
        }
        Task { @MainActor in self.handle(msg) }
    }
}
```

**Step 3: Manual verification**

1. Build, run.
2. Sign in to a site you don't have saved (e.g., a personal app you control or a throwaway account).
3. Set a breakpoint on `pendingSaveCredential` setter — confirm it fires with `.save(...)` after success. (Or add a temporary `log.info("pending: \(...)")` line and watch Console.)
4. Sign in again with the same credentials — confirm the no-op (no `pendingSaveCredential` change).

**Step 4: Commit**
```bash
git add Browse/Passwords
git commit -m "feat(passwords): decode bridge messages and compute pending save state"
```

---

### Task 9: `SavePromptOverlay` + `SavePromptView`

**Files:**
- Create: `Browse/Passwords/SavePromptOverlay.swift`
- Create: `Browse/Passwords/SavePromptView.swift`
- Modify: `Browse/WebContent/WebViewController.swift`

**Step 1: Create `SavePromptView.swift`** — SwiftUI form per the design doc.

```swift
import SwiftUI

struct SavePromptView: View {
    enum Mode { case save, update }

    let mode: Mode
    let site: String
    @State var username: String
    @State var password: String
    @State private var revealPassword = false
    let onSubmit: (_ username: String, _ password: String) -> Void
    let onNever: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(Constants.Colors.foregroundPrimary.swiftUI)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.Colors.foregroundPrimary.swiftUI)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Constants.Colors.foregroundMuted.swiftUI)
                }
                .buttonStyle(.plain)
            }
            if mode == .update {
                Text("This will replace your saved password for \(username).")
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.Colors.foregroundSecondary.swiftUI)
            }
            labelled("Username") {
                TextField("", text: $username).textFieldStyle(.roundedBorder)
            }
            labelled("Password") {
                HStack(spacing: 6) {
                    Group {
                        if revealPassword {
                            TextField("", text: $password)
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button {
                        revealPassword.toggle()
                    } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                            .foregroundStyle(Constants.Colors.foregroundMuted.swiftUI)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Never for this site", action: onNever)
                    .buttonStyle(.plain)
                    .foregroundStyle(Constants.Colors.foregroundSecondary.swiftUI)
                Spacer()
                Button(primaryLabel) { onSubmit(username, password) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(Constants.Colors.surfacePrimary.swiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Constants.Colors.borderLight.swiftUI, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
    }

    private var title: String {
        switch mode {
        case .save:   return "Save password for \(site)?"
        case .update: return "Update password for \(site)?"
        }
    }
    private var primaryLabel: String { mode == .save ? "Save" : "Update" }

    @ViewBuilder
    private func labelled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Constants.Colors.foregroundSecondary.swiftUI)
            content()
        }
    }
}
```

> Note: this assumes there is a `swiftUI` accessor on the `NSColor` tokens in `Constants.swift` (or equivalent). If not, replace with `Color(<NSColor>)` inline. Don't hardcode hex.

**Step 2: Create `SavePromptOverlay.swift`** — the AppKit shell that hosts the SwiftUI view in the top-left of the web view.

```swift
import AppKit
import SwiftUI

final class SavePromptOverlay: NSView {
    private var hosting: NSHostingView<SavePromptView>?

    func show(view: SavePromptView, in container: NSView) {
        if hosting?.superview != nil { hide() }
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(x: 0, y: 0, width: 360, height: hostingHeight(for: view))
        let wrapper = NSView(frame: host.frame) // keep CLAUDE.md rule: never set NSHostingView as self.view directly
        wrapper.addSubview(host)
        host.autoresizingMask = [.width, .height]
        addSubview(wrapper)

        // Animate in: top-left of container with 12pt padding.
        wrapper.frame = NSRect(
            x: 12,
            y: container.bounds.height - wrapper.frame.height - 12,
            width: 360,
            height: wrapper.frame.height
        )
        wrapper.autoresizingMask = [.minYMargin]
        wrapper.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            wrapper.animator().alphaValue = 1
        }
        hosting = host
    }

    func hide() {
        guard let host = hosting else { return }
        let wrapper = host.superview
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            wrapper?.animator().alphaValue = 0
        } completionHandler: { [weak wrapper] in
            wrapper?.removeFromSuperview()
        }
        hosting = nil
    }

    private func hostingHeight(for view: SavePromptView) -> CGFloat {
        view.mode == .update ? 210 : 180
    }
}
```

**Step 3: Wire into `WebViewController.swift`.** Add a stored property:

```swift
private let savePromptOverlay = SavePromptOverlay()
```

Add an observation of `coordinator.pendingSaveCredential` — the simplest robust pattern in this codebase is to drive it from the same `Task` that already polls in `BrowserWindowController`. Add:

```swift
private func observeCoordinator() {
    guard let coordinator = passwordCoordinator else { return }
    Task { @MainActor [weak self] in
        var last: PasswordManagerCoordinator.PendingCredential? = nil
        while !Task.isCancelled {
            guard let self else { return }
            let current = coordinator.pendingSaveCredential
            if current != last {
                self.applyPendingSaveCredential(current)
                last = current
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

private func applyPendingSaveCredential(_ pending: PasswordManagerCoordinator.PendingCredential?) {
    guard let pending else { savePromptOverlay.hide(); return }
    let view: SavePromptView
    switch pending {
    case let .save(site, username, password):
        view = SavePromptView(mode: .save, site: site, username: username, password: password,
                              onSubmit: { [weak self] u, p in self?.handleSave(.save(site: site, username: u, password: p)) },
                              onNever:  { [weak self] in self?.handleNever(site: site) },
                              onClose:  { [weak self] in self?.handleDismiss() })
    case let .update(site, username, password, existingId):
        view = SavePromptView(mode: .update, site: site, username: username, password: password,
                              onSubmit: { [weak self] u, p in self?.handleSave(.update(site: site, username: u, password: p, existingId: existingId)) },
                              onNever:  { [weak self] in self?.handleNever(site: site) },
                              onClose:  { [weak self] in self?.handleDismiss() })
    }
    savePromptOverlay.show(view: view, in: self.view)
}
```

Add the action handlers in `WebViewController`:

```swift
private func handleSave(_ pending: PasswordManagerCoordinator.PendingCredential) {
    switch pending {
    case let .save(site, username, password):
        passwordStore.save(Credential(site: site, username: username, password: password))
    case let .update(_, _, password, existingId):
        passwordStore.update(id: existingId, password: password)
    }
    passwordCoordinator?.pendingSaveCredential = nil
}

private func handleNever(site: String) {
    blocklistStore.add(site)
    passwordCoordinator?.pendingSaveCredential = nil
}

private func handleDismiss() {
    passwordCoordinator?.pendingSaveCredential = nil
}
```

Call `observeCoordinator()` once after the coordinator is created.

Add the overlay to the view hierarchy when the web view is laid in. In your existing layout method:

```swift
// after addSubview(webViewHost):
addSubview(savePromptOverlay, positioned: .above, relativeTo: webViewHost)
savePromptOverlay.frame = self.view.bounds
savePromptOverlay.autoresizingMask = [.width, .height]
```

`SavePromptOverlay` is itself a transparent container; the actual UI lives inside it as a smaller positioned subview.

**Step 4: Manual verification**

1. Build, run, navigate to a site you can log into with a fresh credential (a throwaway account works).
2. Sign in successfully. Within ~1s the prompt should fade in at the top-left of the web view.
3. Verify the username field is editable, the password field is masked with an eye toggle that reveals it.
4. Click **Save**. Prompt disappears.
5. Open the macOS **Passwords** app (System Settings → Passwords). Find the entry labeled "Browse — yoursite.com". Confirm the username and password match.
6. Sign out and sign back in with a *new* password. The **Update** variant should appear instead. Click Update and verify the password changes in the Passwords app.
7. Sign in to a different test site, click **Never for this site**. Sign out and sign back in — the prompt should not appear.

**Step 5: Commit**
```bash
git add Browse/Passwords Browse/WebContent/WebViewController.swift
git commit -m "feat(passwords): save/update prompt overlay in top-left of web view"
```

---

### Task 10: 15s auto-dismiss timer with tab-switch pause/resume

**Files:**
- Modify: `Browse/Passwords/PasswordManagerCoordinator.swift`

**Step 1: Add timer state and per-tab visibility tracking.**

```swift
// Inside PasswordManagerCoordinator:

private var saveDeadline: Date?      // Date by which the prompt expires; pauses while inactive.
private var savePauseTime: Date?     // When the timer was paused (tab inactive).
private var saveTimer: Task<Void, Never>?
var isTabActive: Bool = true {
    didSet {
        guard oldValue != isTabActive else { return }
        if isTabActive { resumeSaveTimer() } else { pauseSaveTimer() }
    }
}

private func startSaveTimer() {
    cancelSaveTimer()
    saveDeadline = Date().addingTimeInterval(15)
    scheduleExpiry()
}

private func scheduleExpiry() {
    guard let deadline = saveDeadline else { return }
    let interval = deadline.timeIntervalSinceNow
    saveTimer = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(max(0, interval)))
        guard !Task.isCancelled, let self else { return }
        if self.saveDeadline != nil, Date() >= self.saveDeadline! {
            self.pendingSaveCredential = nil
            self.saveDeadline = nil
        }
    }
}

private func pauseSaveTimer() {
    guard saveDeadline != nil else { return }
    savePauseTime = Date()
    saveTimer?.cancel()
    saveTimer = nil
}

private func resumeSaveTimer() {
    guard let deadline = saveDeadline, let paused = savePauseTime else { return }
    let pausedFor = Date().timeIntervalSince(paused)
    saveDeadline = deadline.addingTimeInterval(pausedFor)
    savePauseTime = nil
    scheduleExpiry()
}

private func cancelSaveTimer() {
    saveTimer?.cancel()
    saveTimer = nil
    saveDeadline = nil
    savePauseTime = nil
}
```

**Step 2: Hook timer to `pendingSaveCredential`.** In the property's `didSet`:

```swift
var pendingSaveCredential: PendingCredential? {
    didSet {
        if pendingSaveCredential == nil {
            cancelSaveTimer()
        } else {
            startSaveTimer()
        }
    }
}
```

**Step 3: Wire `isTabActive`.** In `TabManager` (or wherever active tab is tracked), notify each tab's coordinator when it becomes active/inactive. Concretely: in `WebViewController`, override `viewWillAppear` / `viewWillDisappear`:

```swift
override func viewWillAppear() {
    super.viewWillAppear()
    passwordCoordinator?.isTabActive = true
}

override func viewWillDisappear() {
    super.viewWillDisappear()
    passwordCoordinator?.isTabActive = false
}
```

Per CLAUDE.md, "only the active tab's web view is in the view hierarchy" — so `viewWillAppear` / `viewWillDisappear` correspond to tab activations.

**Step 4: Manual verification**

1. Sign in to a fresh test site → save prompt appears.
2. Wait 15 seconds without interacting → prompt disappears (timer expired, treated as "Not now").
3. Sign in again → prompt reappears.
4. Switch to a different tab within ~5 seconds, wait 30 seconds, switch back → prompt should still be visible. (Timer paused while tab was inactive.)

**Step 5: Commit**
```bash
git add Browse/Passwords/PasswordManagerCoordinator.swift Browse/WebContent/WebViewController.swift
git commit -m "feat(passwords): 15s save prompt auto-dismiss with tab-switch pause/resume"
```

---

## Phase 5 — Autofill popover

After this phase, focusing a known login field on a saved site shows a native popover anchored below the field with the matching credentials, and clicking one fills both username and password.

### Task 11: `AutofillPopoverPanel` + `AutofillPopoverView`

**Files:**
- Create: `Browse/Passwords/AutofillPopoverView.swift`
- Create: `Browse/Passwords/AutofillPopoverPanel.swift`

**Step 1: Create `AutofillPopoverView.swift`.**

```swift
import SwiftUI

struct AutofillPopoverView: View {
    let credentials: [Credential]
    @Binding var selectedIndex: Int
    let onSelect: (Credential) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(credentials.enumerated()), id: \.element.id) { idx, cred in
                            row(for: cred, isSelected: idx == selectedIndex)
                                .id(cred.id)
                                .onTapGesture { onSelect(cred) }
                                .onHover { inside in if inside { selectedIndex = idx } }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, new in
                    if credentials.indices.contains(new) {
                        proxy.scrollTo(credentials[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 240)
        .background(Constants.Colors.surfacePrimary.swiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Constants.Colors.borderLight.swiftUI, lineWidth: 1)
        )
    }

    private func row(for cred: Credential, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Constants.Colors.accentPrimary.swiftUI)
                .frame(width: 24, height: 24)
                .overlay(Text(initial(cred.username))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(cred.username)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Constants.Colors.foregroundPrimary.swiftUI)
                Text(cred.site)
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.Colors.foregroundSecondary.swiftUI)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground(isSelected: isSelected))
        .contentShape(Rectangle())
    }

    private func rowBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected { Constants.Colors.hoverBg.swiftUI } else { Color.clear }
        }
    }

    private func initial(_ s: String) -> String {
        String(s.first ?? "?").uppercased()
    }
}
```

**Step 2: Create `AutofillPopoverPanel.swift`.**

```swift
import AppKit
import SwiftUI

@MainActor
final class AutofillPopoverPanel {
    private let panel: NSPanel
    private var hosting: NSHostingView<AutofillPopoverView>?
    private var credentials: [Credential] = []
    private var selectedIndex = 0
    private var onSelect: ((Credential) -> Void)?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = true
        let wrapper = NSView()
        panel.contentView = wrapper
    }

    func show(below fieldRect: CGRect, in window: NSWindow,
              credentials: [Credential],
              onSelect: @escaping (Credential) -> Void) {
        guard !credentials.isEmpty else { return }
        self.credentials = credentials
        self.selectedIndex = 0
        self.onSelect = onSelect

        let view = AutofillPopoverView(credentials: credentials,
                                       selectedIndex: Binding(
                                            get: { [weak self] in self?.selectedIndex ?? 0 },
                                            set: { [weak self] in self?.selectedIndex = $0 }),
                                       onSelect: { [weak self] cred in
                                            self?.hide()
                                            onSelect(cred)
                                       })
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        if let wrapper = panel.contentView {
            wrapper.subviews.forEach { $0.removeFromSuperview() }
            wrapper.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: wrapper.topAnchor),
                host.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ])
        }
        hosting = host

        let preferred = NSSize(width: 280, height: min(240, max(48, CGFloat(credentials.count) * 48)))
        var origin = NSPoint(x: fieldRect.minX, y: fieldRect.maxY + 4)
        // Flip above field if it would clip the screen
        if let screen = window.screen {
            if origin.y + preferred.height > screen.visibleFrame.maxY {
                origin.y = fieldRect.minY - preferred.height - 4
            }
        }
        panel.setFrame(NSRect(origin: origin, size: preferred), display: true)
        panel.orderFront(nil)
        installMonitors()
    }

    func hide() {
        panel.orderOut(nil)
        removeMonitors()
        credentials = []
        onSelect = nil
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.isVisible else { return ev }
            switch ev.keyCode {
            case 125: // arrow down
                self.selectedIndex = min(self.selectedIndex + 1, self.credentials.count - 1)
                return nil
            case 126: // arrow up
                self.selectedIndex = max(self.selectedIndex - 1, 0)
                return nil
            case 36: // return
                if self.credentials.indices.contains(self.selectedIndex) {
                    let cred = self.credentials[self.selectedIndex]
                    self.hide()
                    self.onSelect?(cred)
                }
                return nil
            case 53: // escape
                self.hide()
                return nil
            default: return ev
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let c = clickMonitor { NSEvent.removeMonitor(c); clickMonitor = nil }
    }
}
```

**Step 3: Add to Xcode project, build.** (No wiring yet — built in Task 12.)

**Step 4: Commit**
```bash
git add Browse/Passwords/AutofillPopoverPanel.swift Browse/Passwords/AutofillPopoverView.swift Blur-Browser.xcodeproj/project.pbxproj
git commit -m "feat(passwords): autofill popover panel and view"
```

---

### Task 12: Wire `fieldFocused` → popover with rect translation

**Files:**
- Modify: `Browse/Passwords/PasswordManagerCoordinator.swift`
- Modify: `Browse/WebContent/WebViewController.swift`

**Step 1: Coordinator side — handle focus events.**

```swift
// New stored property:
private var lastDetectedForms: [DetectedForm] = []

// Update handle(_:):
case .formsDetected(_, let forms):
    self.lastDetectedForms = forms
case .fieldFocused(let unitId, let fieldId, let role, let rect):
    presentAutofillIfPossible(unitId: unitId, fieldId: fieldId, role: role, rectInDoc: rect.cgRect)
case .fieldBlurred:
    onAutofillDismiss?()
case .viewportChanged:
    onAutofillDismiss?()
```

```swift
// New callbacks (set by WebViewController):
var onAutofillPresent: ((CGRect, [Credential], _ form: DetectedForm) -> Void)?
var onAutofillDismiss: (() -> Void)?

private func presentAutofillIfPossible(unitId: String, fieldId: String, role: FieldRole, rectInDoc: CGRect) {
    guard role == .username || role == .password else { return }
    guard let url = webView?.url, let site = SiteIdentity.key(for: url) else { return }
    let credentials = passwordStore.lookup(forSite: site)
    guard !credentials.isEmpty else { return }
    guard let form = lastDetectedForms.first(where: { $0.unitId == unitId }) else { return }
    onAutofillPresent?(rectInDoc, credentials, form)
}
```

**Step 2: WebViewController side — translate rect and show panel.**

```swift
private let autofillPanel = AutofillPopoverPanel()

// In observeCoordinator() / setup, set callbacks:
coordinator.onAutofillPresent = { [weak self] rectInDoc, creds, form in
    self?.presentAutofill(rectInDoc: rectInDoc, credentials: creds, form: form)
}
coordinator.onAutofillDismiss = { [weak self] in
    self?.autofillPanel.hide()
}

private func presentAutofill(rectInDoc: CGRect, credentials: [Credential], form: DetectedForm) {
    guard let webView, let window = webView.window else { return }
    // 1. CSS px (top-doc) -> WKWebView coords (just match its bounds origin since web content is at origin):
    let webViewRect = NSRect(
        x: rectInDoc.minX,
        y: webView.bounds.height - rectInDoc.maxY, // flip Y: docs grow down, AppKit grows up
        width: rectInDoc.width,
        height: rectInDoc.height
    )
    // 2. webView -> window coords:
    let windowRect = webView.convert(webViewRect, to: nil)
    // 3. window -> screen coords:
    let screenRect = window.convertToScreen(windowRect)
    autofillPanel.show(below: screenRect, in: window, credentials: credentials) { [weak self] cred in
        self?.fillCredential(cred, into: form)
    }
}

private func fillCredential(_ cred: Credential, into form: DetectedForm) {
    guard let webView else { return }
    let payload: [String: Any] = [
        "usernameFieldId": form.usernameFieldId ?? "",
        "username": cred.username,
        "passwordFieldId": form.passwordFieldId,
        "password": cred.password,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return }
    webView.evaluateJavaScript("__BrowsePasswordManager.fillCredential(\(json))")
}
```

**Step 3: Tab-switch / window-deactivate dismiss.**

In `WebViewController.viewWillDisappear`, call `autofillPanel.hide()`. Also subscribe to `NSWindow.didResignKeyNotification` once at setup and hide the panel on resign.

**Step 4: Manual verification**

1. Save a credential for a test site (use the save prompt flow).
2. Sign out, return to the login page, click into the username field.
3. Popover appears anchored below the field with the saved credential. Click it → both fields fill, the page's "Sign In" button becomes enabled (proves the `input`/`change` events fired correctly).
4. Repeat for sites with multiple saved credentials (save two for the same site first). Use ↓/↑ to navigate, ↩ to fill.
5. Press Esc — popover hides.
6. Open popover, scroll the page → popover hides.
7. Open popover, switch tabs → popover hides.

**Step 5: Commit**
```bash
git add Browse/Passwords/PasswordManagerCoordinator.swift Browse/WebContent/WebViewController.swift
git commit -m "feat(passwords): show autofill popover on field focus and fill on selection"
```

---

## Phase 6 — Polish & verification

### Task 13: HTTP refusal + final manual test matrix

**Files:**
- Modify: documentation only (the HTTP refusal is already enforced by `SiteIdentity.key(for:)` returning nil for non-https URLs in Task 1).

**Step 1: Verify HTTP refusal.** Open `http://example.com` (or any HTTP page) with a password form. Type credentials and submit. Expect: no save prompt appears. Console should log no `loginLikelySucceeded` handling. (The JS still posts events; the coordinator's `handleSuccess` bails because `SiteIdentity.key(for:)` returns nil for HTTP.)

If the bail isn't happening, confirm `SiteIdentity.key(for:)` rejects HTTP and that `handleSuccess` calls it (not `site(for:)`).

**Step 2: Run the full manual test matrix.**

| Site | Action | Expected |
|---|---|---|
| `https://github.com/login` | Focus username | No popover (no creds saved) |
| `https://github.com/login` | Sign in successfully | Save prompt appears top-left |
| `https://github.com/login` | Save → sign out → return → focus username | Popover with saved cred |
| `https://github.com/login` | Click cred in popover | Both fields fill, Sign In becomes enabled |
| `https://github.com/login` | Sign in with wrong password | No save prompt (loginInconclusive) |
| `https://github.com/settings/security` | Change password | Update prompt appears |
| `https://github.com/signup` | Create account, complete signup | Save prompt appears (classified as signup) |
| `https://app.linear.app/` | Sign in | Save prompt appears (SPA, success via pushState) |
| `https://news.ycombinator.com/login` | Sign in | Save prompt appears (no autocomplete attrs — heuristic path) |
| `https://gmail.com/` | Sign in (Google's multi-step flow) | Save prompt appears for the password step |
| `http://example.com/login-form` | Sign in | **No** save prompt (HTTP refused) |
| `https://github.com/login` | Save credential, click "Never for this site", sign out, sign in again | No save prompt |
| `https://github.com/login` | Sign in twice with same creds | Save prompt only first time (no-op on second) |
| Any saved-site login | Wait 15s without clicking Save | Prompt fades out |
| Any saved-site login | Show prompt, switch to other tab for 30s, return | Prompt still visible |
| Any saved-site login | Show popover, scroll page | Popover hides |

**Step 3: Verify Apple Passwords integration.** Open System Settings → Passwords. Confirm at least one entry labeled `Browse — <site>` exists with the saved username and password. Edit it from there and verify a fresh `lookup` from Browse picks up the change.

**Step 4: Commit (only if any fixes were needed during the matrix).** If everything works, no commit; the test matrix is verification, not code.

```bash
git add docs/plans/2026-04-27-password-manager.md
git commit -m "docs(passwords): manual verification matrix complete"
```

---

## What we built

After completing all tasks:

- 8 new Swift files in `Browse/Passwords/` (~700 lines of native code)
- 1 new JS file (~250 lines)
- 3 modified files: `WebViewConfiguration.swift`, `WebViewController.swift`, `BrowserWindowController.swift`
- Saved credentials live in the user's Keychain, sync via iCloud Keychain when enabled, and appear in Apple's Passwords app
- Autofill popover for known sites with keyboard nav
- Save / update / never-for-this-site prompt on successful login, signup, and change-password
- Same-origin iframes handled
- HTTP sites refused
- 15s auto-dismiss with tab-switch pause/resume

## What we didn't build (per design doc)

- Password generation
- Biometric / Touch ID auth gate
- Settings UI for managing saved passwords (use Apple Passwords app)
- Import / export
- Cross-origin iframes
- Public Suffix List (naive eTLD+1 only)
- 2FA / OTP autofill
- Password strength indicators / breach checks
- Per-path / per-URL credential scoping
- Private browsing mode

---

## Execution

Plan complete and saved to [`docs/plans/2026-04-27-password-manager.md`](./2026-04-27-password-manager.md). Two execution options:

**1. Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Stay in this conversation.

**2. Parallel Session (separate)** — Open a new session with the executing-plans skill, batch execution with checkpoints. Useful if you want to start the work later or have me free to do something else in parallel.

Which approach?
