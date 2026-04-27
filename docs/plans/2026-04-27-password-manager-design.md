# Password Manager — Design

**Date:** 2026-04-27
**Status:** Design approved, ready for implementation planning
**Scope:** v1 — autofill UI, form detection, save-on-success prompt

## v1 Goal

Add a built-in password manager to Browse covering three user-visible features:

1. **Autofill UI** — when the user focuses a known login field on a site we have credentials for, show a native popover anchored to the field listing the saved credentials. Click one to fill.
2. **Form detection** — automatically detect login, signup, and change-password forms across normal pages and SPAs.
3. **Save / update prompt** — after a successful login (or signup, or password change), show a prompt in the top-left of the web view offering to save or update the credential.

Storage uses the system Keychain (`kSecClassInternetPassword`) so saved entries appear in Apple's Passwords app and sync via iCloud Keychain when enabled. Browse does **not** read from Apple's Safari-managed passwords (different keychain access group, sandboxed off from third-party apps).

## Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Login success heuristic | Form submit → within 3s, password field disappears OR URL changes (incl. SPA `pushState`/`replaceState`) | Standard browser approach; SPA-aware. |
| Autofill UI mechanism | Native SwiftUI popover anchored to focused field (no HTML injection) | Cannot be styled-over or intercepted by sites. Matches Browse's existing `QuickSearchPanel` overlay pattern. |
| Form detection | `autocomplete` attributes first, heuristic fallback; classify login / signup / change-password / 2FA | Covers modern HTML and lets us behave correctly on signup and password-change pages. |
| Signup behavior | Save new credential on success if user accepts. **No password generation.** | YAGNI for v1. |
| Change-password behavior | Offer to update existing credential on success. **No password generation.** | YAGNI for v1. |
| 2FA / OTP forms | Detected and ignored | Out of scope. |
| Save prompt placement | Top-left of web view, 12pt padding | User decision. |
| Save prompt UX | Editable username, masked password with reveal toggle, **Save** / **Never for this site** / `×` close, 15s auto-dismiss | Matches established browser patterns; "Never" is essential to avoid noise on banking sites. |
| Site matching | Naive eTLD+1 (last two labels) | Pragmatic v1; PSL upgrade documented as future work. |
| iframe scope | Same-origin iframes only | Cross-origin iframes are rare for login (most providers open new windows), and bring real security complications. |
| HTTP sites | Not saved | Refuse to save credentials transmitted insecurely. |
| Biometric / Touch ID auth | Not in v1 | Relies on macOS login session. |
| Settings UI | Not in v1 | Manage entries via Apple's Passwords app. |
| Storage | Keychain (`kSecClassInternetPassword`), `kSecAttrSynchronizable = true` | Native, encrypted, iCloud-syncable, integrates with system Passwords app. |

## Architecture

Three layers mirroring Browse's existing AppKit-host / SwiftUI-embed pattern.

### Layer 1 — JS content script

`passwordManager.js`, ~250 lines, injected via `WKUserContentController.addUserScript` at `WKUserScriptInjectionTime.atDocumentEnd` with `forMainFrameOnly: false`. Runs in every same-origin frame.

### Layer 2 — Native bridge

`PasswordManagerCoordinator` — `@MainActor @Observable` class. Owns:
- a `WKScriptMessageHandler` registered for the message name `passwordManager`
- per-tab state (`[ObjectIdentifier: TabState]`) keyed by `WKWebView` identity
- the autofill popover (`AutofillPopoverPanel`) and save prompt overlay (`SavePromptOverlay`)
- references to `PasswordStore` and `BlocklistStore`

One coordinator instance per `BrowserTab`, owned by `WebViewController`. Wired up in `WebViewConfiguration.swift`.

### Layer 3 — Storage

- `PasswordStore` — plain `final class` wrapping Keychain Services. Stateless, no observation needed.
- `BlocklistStore` — plain `final class` wrapping `UserDefaults` for "Never for this site" entries.

Stores are owned by `BrowserWindowController` (one per window) and passed into `PasswordManagerCoordinator` via initializer, mirroring how `HistoryStore` is wired today.

### File map

```
Browse/Passwords/
├── PasswordManagerCoordinator.swift   # @MainActor @Observable — owns UI state
├── PasswordStore.swift                 # plain final class, Keychain wrapper
├── BlocklistStore.swift                # plain final class, UserDefaults wrapper
├── SiteIdentity.swift                  # enum namespace, pure functions
├── Credential.swift                    # value type
├── AutofillPopoverPanel.swift          # NSPanel + NSHostingView shell
├── AutofillPopoverView.swift           # SwiftUI list of credentials
├── SavePromptOverlay.swift             # NSView + NSHostingView shell
├── SavePromptView.swift                # SwiftUI save / update form
└── Resources/passwordManager.js        # Layer 1 content script
```

Modifications:
- `Browse/WebContent/WebViewConfiguration.swift` — register the user script and message handler.
- `Browse/WebContent/WebViewController.swift` — own a `PasswordManagerCoordinator`, attach the save prompt overlay, position the autofill panel.

`@Observable` rule of thumb baked into the design: `@Observable` for things SwiftUI views or polling loops watch (`PasswordManagerCoordinator`); plain types for everything else (`PasswordStore`, `BlocklistStore`, `SiteIdentity`, `Credential`).

## Form detection (Layer 1 detail)

### Boot sequence

1. Initial `scan()` on script load.
2. Install `MutationObserver` on `document.body` (subtree, attribute changes for `type` / `autocomplete`) to re-scan when the DOM changes — covers React/Vue forms rendered after initial paint. Re-scans debounced to 150ms.
3. Install global capture-phase listeners: `focusin`, `submit`, `click`. Capture-phase ensures we run before site listeners can `stopPropagation`.
4. Monkey-patch `window.history.pushState` and `window.history.replaceState` to fire a synthetic `__bm_locationChanged` `CustomEvent` so the success watcher can detect SPA navigations.
5. Post `scriptReady{site}` to native.

### `scan()` algorithm

```
1. Find every <input type="password"> in the document.
2. For each password input, identify the "form unit" it belongs to:
   - Its <form> ancestor if any
   - Otherwise, the nearest containing element with multiple inputs
3. Identify the username field within the unit:
   - Prefer autocomplete="username" or autocomplete="email"
   - Otherwise, the nearest preceding <input> of type text|email|tel
   - Otherwise, null
4. Classify the unit:
   - autocomplete="new-password" present, OR 2+ password fields → SIGNUP
   - autocomplete="current-password" AND autocomplete="new-password"
     in same unit → CHANGE_PASSWORD
   - Submit button text or form id/class matches
     /sign\s*up|register|create.*account/i → SIGNUP
   - Submit button text or form id/class matches
     /change|update.*password|new.*password/i → CHANGE_PASSWORD
   - Default → LOGIN
5. Tag fields with stable UUIDs (data-bm-field-id="<uuid>") so native
   can later say "fill into field <uuid>" without re-finding it.
6. Post `formsDetected{site, forms[]}` to native.
```

Multiple-password-field handling: signup pages with "Password" + "Confirm password" both match — we use the **first** as the credential, ignore the second.

### Submission tracking

On `submit` event (capture-phase) OR `click` on a button matching `[type=submit]` inside the unit OR text matching `/log\s*in|sign\s*in|continue|submit/i`:
1. Snapshot the current values of `usernameField` and `passwordField`.
2. Post `formSubmitted{unitId, classification, username, password}` to native.
3. Enter "watch for success" mode for this `unitId`: start a 3000ms timer.

### Success heuristic (the 3-second window)

Within 3s of `formSubmitted`, fire `loginLikelySucceeded{unitId}` if **either**:
- The element bearing `data-bm-field-id == passwordFieldId` is no longer in the DOM, OR has computed `display: none` / `visibility: hidden`, OR has `value === ""` and lost focus, OR
- A real navigation happened (`beforeunload` fired and a new document loaded), OR
- A SPA navigation happened (`__bm_locationChanged` event fired from our patched `pushState` / `replaceState`).

If 3s elapses with neither, fire `loginInconclusive{unitId}` and the native side discards the pending credential.

### Iframe coordinate translation

Same-origin iframe scripts walk up `window.parent` accumulating `frameElement.getBoundingClientRect()` offsets, so reported field rects are always in the **top document's** coordinate space. The native side never has to know which frame a focus came from.

### Filling

The script exposes a small global `window.__BrowsePasswordManager` object with three entry points (called from native via `evaluateJavaScript`):

```js
__BrowsePasswordManager.fillField({ fieldId, value })
__BrowsePasswordManager.fillCredential({ usernameFieldId, username,
                                         passwordFieldId, password })
__BrowsePasswordManager.rescan()
```

`fillField` sets `.value`, then dispatches `input` and `change` events with `{ bubbles: true }`, plus a synthetic `keydown` + `keyup` for sites listening on those (some validation libraries do). React/Vue controlled inputs need the events to update their internal state.

## Autofill popover (Layer 2 detail)

### Surface

`AutofillPopoverPanel` — borderless `NSPanel` subclass:
- `styleMask: [.borderless, .nonactivatingPanel]` — does not steal key window status from `BrowserWindow`, so the user can keep typing in the focused field while the popover is visible.
- `level: .floating`, `hasShadow: true`, `isMovable: false`, `isOpaque: false`, `backgroundColor: .clear`.
- Content view is a plain `NSView` containing `NSHostingView<AutofillPopoverView>` with `sizingOptions = []` (per CLAUDE.md anti-layout-cycle rule).

### `AutofillPopoverView` (SwiftUI)

- Width: 280pt. Height dynamic, capped at 240pt with internal scroll.
- Visual: 10pt rounded corners, `surfacePrimary` background, 1pt `borderLight` stroke, soft 16pt drop shadow (set on the panel, not the view).
- One row per credential:
  - 24pt circle on the left with first letter of username, `accentPrimary` background, white text.
  - Username text in `foregroundPrimary` 13pt Inter Medium.
  - Site host below in `foregroundSecondary` 11pt Inter Regular.
  - Hover: `hoverBg`. Selected (keyboard nav): `accentPrimary` 10% tint.
- Footer row: small key SF Symbol + "Manage saved passwords…". Hidden in v1 (no settings UI yet).
- Empty state (zero credentials for site): popover does not show at all.

### Trigger flow

1. JS posts `fieldFocused{unitId, fieldId, role, rect}`.
2. Coordinator calls `PasswordStore.lookup(forSite: site)` where `site` is derived from `webView.url`. If empty → bail.
3. Translate the JS-reported viewport-relative rect (CSS px) to screen coords:
   - `webView.convert(rect, to: nil)` → `webView.window?` coords.
   - `webView.window?.convertToScreen(...)` → screen coords.
4. Position the panel 4pt below the field's bottom edge, left-aligned to the field. If the panel would clip the bottom of the screen, flip above the field.
5. Show with `panel.orderFront(nil)`.

### Keyboard

`AutofillPopoverView` installs an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` while the panel is visible:
- ↓ / ↑ navigates rows.
- ↩ fills the highlighted row.
- Esc hides the panel.

### Selection & filling

Click a row → coordinator sends `fillCredential{ usernameFieldId, username, passwordFieldId, password }` → panel hides.

### Dismiss conditions

- JS posts `fieldBlurred{fieldId}` → hide.
- JS posts `viewportChanged` (page scrolled) → hide. Re-shows on next field focus rather than tracking continuously.
- User clicks outside the panel (global event monitor) → hide.
- Tab switches or window deactivates → hide.

## Save / update prompt (Layer 2 detail)

### Surface

`SavePromptOverlay` — *not* an `NSPanel`. Sits inside the web view's frame as a regular subview of `WebViewController.view`:

```swift
overlay.frame = NSRect(x: 12,
                       y: webViewBounds.height - overlayHeight - 12,
                       width: 360,
                       height: overlayHeight)
overlay.autoresizingMask = [.minYMargin]   // sticks to top-left
```

Z-order: added with `addSubview(_:positioned: .above, relativeTo: webViewHost)` so it sits above the WKWebView surface.

Container is a plain `NSView` holding `NSHostingView<SavePromptView>` with `sizingOptions = []`.

### `SavePromptView` (SwiftUI)

- Width 360pt. Height ~180pt for save, ~210pt for update (extra row).
- Visual: 12pt rounded corners, `surfacePrimary` bg, 1pt `borderLight` stroke, 20pt soft shadow.
- Header row:
  - Small key SF Symbol + title:
    - Save: "Save password for `example.com`?"
    - Update: "Update password for `example.com`?"
  - Close `×` button on the right.
- Update variant only: subtitle row "This will replace your saved password for `<username>`."
- Username field — editable `TextField`, prefilled, label "Username".
- Password field — `SecureField` with eye-toggle button to reveal/mask, label "Password".
- Button row, right-aligned:
  - **Never for this site** — plain text button, `foregroundSecondary`.
  - **Save** / **Update** — filled button, `accentPrimary` bg, white text, ⌘↩ keyboard shortcut.

### Coordinator state

```swift
@Observable
final class PasswordManagerCoordinator {
    var pendingSaveCredential: PendingCredential?

    enum PendingCredential {
        case save(site: String, username: String, password: String)
        case update(site: String, username: String, password: String, existingId: UUID)
    }
}
```

`SavePromptView` binds to this property; setting it to `nil` hides the overlay (with a 150ms `.move(edge: .top).combined(with: .opacity)` transition).

### Lifecycle

1. JS posts `loginLikelySucceeded{unitId}`.
2. Coordinator looks up the cached `formSubmitted` payload for that unitId, then queries `PasswordStore.lookup(forSite: site)`. Decision matrix:

   | Submitted | Existing for site | Action |
   |---|---|---|
   | `user / pw` | nothing, or no entry with `user` | `.save(...)` |
   | `user / new_pw` | `user / old_pw` | `.update(...)` |
   | `user / pw` | `user / pw` (identical) | **No-op** — already saved, nothing to update |
   | (any) | site is in blocklist | **No-op** |

3. Coordinator starts a 15s timer. On expiry → `pendingSaveCredential = nil` (treated as "Not now"; will re-prompt on the next successful login).
4. Timer **pauses** when the tab is not active. Resumes when the user returns to the tab.
5. User actions:
   - **Save** / **Update** → `PasswordStore.save(...)` or `.update(existingId, password:)` → clear pending → hide overlay.
   - **Never for this site** → `BlocklistStore.add(site)` → clear pending → hide overlay.
   - **×** click or Esc → clear pending → hide overlay (re-prompts on next successful login).

### One-at-a-time

If a fresh `loginLikelySucceeded` arrives while a prompt is already showing, the new pending credential replaces the old one. Stale prompts shouldn't block fresh ones.

### Tab switching

The overlay belongs to `WebViewController`, which is per-tab. Per CLAUDE.md, only the active tab's web view is in the hierarchy, so an inactive tab's overlay disappears with its web view. Pending state stays alive on the coordinator and the overlay re-attaches when the user returns to the tab.

### Mid-flow navigation

If the user navigates the same tab to a different page before deciding, the pending save state is **preserved** for the full 15s window. They can still hit Save on the new page. This avoids losing credentials to over-eager redirects (e.g., a successful POST that immediately bounces to a dashboard).

## JS ↔ Native message bridge (full reference)

Single channel name: **`passwordManager`**. JS → native via `window.webkit.messageHandlers.passwordManager.postMessage(payload)`. Each payload has a `kind` discriminator.

Field rects are `{x, y, w, h}` in CSS pixels in the **top document's** coordinate space (iframes pre-translate before posting).

### JS → Native

```jsonc
// 1. Forms detected on the page (initial scan + debounced re-scans, 150ms)
{ "kind": "formsDetected",
  "site": "example.com",
  "forms": [
    { "unitId": "u-1", "classification": "login" | "signup" | "change_password",
      "usernameFieldId": "f-1", "passwordFieldId": "f-2",
      "usernameRect": {...}, "passwordRect": {...} }
  ] }

// 2. A known field was focused → drives autofill popover
{ "kind": "fieldFocused", "unitId": "u-1", "fieldId": "f-1",
  "role": "username" | "password", "rect": {...} }

// 3. Field lost focus → hides autofill popover
{ "kind": "fieldBlurred", "fieldId": "f-1" }

// 4. Page scrolled / viewport resized → hides autofill popover
{ "kind": "viewportChanged" }

// 5. Form submitted → snapshot of values; saved IF success is later confirmed
{ "kind": "formSubmitted", "unitId": "u-1",
  "classification": "login" | "signup" | "change_password",
  "username": "omar@klivvr.com", "password": "hunter2" }

// 6. Success heuristic fired
{ "kind": "loginLikelySucceeded", "unitId": "u-1" }

// 7. 3s window expired without success signal — discard pending save
{ "kind": "loginInconclusive", "unitId": "u-1" }

// 8. Script booted on a new document → reset per-page state on native side
{ "kind": "scriptReady", "site": "example.com" }
```

### Native → JS

Sent via `webView.evaluateJavaScript("window.__BrowsePasswordManager.<fn>(...)")`. Fire-and-forget; no return values needed in v1.

```js
__BrowsePasswordManager.fillField({ fieldId, value })
__BrowsePasswordManager.fillCredential({ usernameFieldId, username,
                                         passwordFieldId, password })
__BrowsePasswordManager.rescan()
```

### Coordinator dispatch

`PasswordManagerCoordinator` implements `WKScriptMessageHandler.userContentController(_:didReceive:)`. The body is decoded into an enum:

```swift
enum InboundMessage: Decodable {
    case formsDetected(site: String, forms: [DetectedForm])
    case fieldFocused(unitId: String, fieldId: String, role: FieldRole, rect: CGRect)
    case fieldBlurred(fieldId: String)
    case viewportChanged
    case formSubmitted(unitId: String, classification: FormClassification,
                       username: String, password: String)
    case loginLikelySucceeded(unitId: String)
    case loginInconclusive(unitId: String)
    case scriptReady(site: String)
}
```

Custom `init(from:)` switches on `kind`. A switch in `didReceive` dispatches to a dedicated handler per case — no string-typing past the boundary.

### Per-tab isolation

`WKScriptMessage.frameInfo.webView` (or the deprecated `webView` property — pick the one available on macOS 14+) identifies which tab sent the message. The coordinator stores per-`WKWebView` state in `[ObjectIdentifier: TabState]`, so messages from background tabs (e.g., a logged-in tab finishing a redirect while the user is on another tab) route to the correct pending-save state.

### Origin verification

For every inbound message, the coordinator independently reads `webView.url?.host` to determine the site. It does **not** trust the `site` field in `formsDetected` / `scriptReady` for keychain decisions — those are advisory and used only for logging. Keychain keys are always derived from the live `webView.url`, so a compromised page can't trick us into saving credentials under another site's identity.

## Storage detail

### `SiteIdentity`

```swift
enum SiteIdentity {
    /// "https://mail.example.com/path" -> "example.com"
    /// v1: naive last-two-labels.
    /// FUTURE: replace with PSL lookup so foo.github.io != bar.github.io.
    static func site(for url: URL) -> String?

    /// Same as site(for:), but enforces our save rules:
    /// - http:// returns nil (we never save credentials over plain HTTP)
    /// - IP addresses return nil
    /// - localhost returns nil
    /// - Hosts with < 2 labels return nil
    static func key(for url: URL) -> String?
}
```

### `Credential`

```swift
struct Credential: Hashable, Identifiable, Sendable {
    let id: UUID
    let site: String         // eTLD+1 from SiteIdentity
    let username: String
    let password: String
    let createdAt: Date
    let updatedAt: Date
}
```

### `PasswordStore` (Keychain)

Class: `kSecClassInternetPassword`.

Item attributes per credential:
- `kSecClass` = `kSecClassInternetPassword`
- `kSecAttrServer` = `site` (eTLD+1, e.g. `"example.com"`)
- `kSecAttrAccount` = `username`
- `kSecAttrLabel` = `"Browse — example.com"` — what shows in Apple's Passwords app
- `kSecAttrCreationDate`, `kSecAttrModificationDate` — managed by Keychain
- `kSecAttrSynchronizable` = `true` → iCloud Keychain sync when enabled
- `kSecAttrAccessible` = `kSecAttrAccessibleWhenUnlocked`
- `kSecAttrGeneric` = JSON-encoded `{ "id": "<uuid>" }` for our stable id
- `kSecValueData` = password as UTF-8 bytes

Operations (synchronous, called from MainActor):
```swift
final class PasswordStore {
    func save(_ cred: Credential)
    func update(id: UUID, password: String)
    func lookup(forSite site: String) -> [Credential]
    func delete(id: UUID)
}
```

Lookup matches `kSecAttrServer == site` exactly. Saving on `mail.example.com` and `accounts.example.com` both resolve to `site = "example.com"` at write time (via `SiteIdentity`), so a single query on `example.com` finds both. No subdomain expansion needed at read time.

Errors (`errSecDuplicateItem`, `errSecAuthFailed`, etc.) are logged via `os_log` and returned from the call site. We don't crash and we don't silently swallow. UI for "save failed" is out of scope for v1.

### `BlocklistStore`

```swift
final class BlocklistStore {
    func contains(_ site: String) -> Bool
    func add(_ site: String)
    func remove(_ site: String)   // for future settings UI
}
```

Backed by `UserDefaults.standard`, key `"BrowsePasswordBlocklist"`, value `[String]` of eTLD+1 sites.

### Ownership

`BrowserWindowController` owns one `PasswordStore` and one `BlocklistStore` per window. They're injected into each tab's `PasswordManagerCoordinator` via initializer, mirroring how `HistoryStore` is wired today.

## Edge cases handled

- **Multiple password fields on signup** — first is the credential, second (confirmation) is ignored.
- **SPA login without navigation** — `pushState` / `replaceState` patched at script load to fire `__bm_locationChanged`.
- **Form re-renders during typing** — `MutationObserver` re-derives field UUIDs; autofill popover hides if focused field id disappears.
- **Tab close mid-prompt** — per-tab `TabState` dropped, pending credential forgotten.
- **Page navigation mid-prompt** — pending state preserved for the full 15s window across navigations within the same tab.
- **Multiple accounts per site** — `lookup(forSite:)` returns a list; popover shows all of them.
- **HTTP sites** — `SiteIdentity.key(for:)` returns nil; coordinator bails before showing any prompt. Logged once per site as a warning.

## Non-goals for v1 (deferred)

1. Password generation on signup or change-password.
2. Biometric / Touch ID auth gate.
3. Settings UI for managing saved passwords (use Apple Passwords app).
4. Import / export.
5. Cross-origin iframes.
6. Public Suffix List (naive eTLD+1 only — known limitation on `*.github.io`, `*.vercel.app`, etc.).
7. 2FA / OTP autofill.
8. Sync conflict resolution (last-write-wins per Keychain default).
9. Password strength indicators / breach checks (no HIBP integration).
10. Per-path / per-URL credential scoping (credentials are per-site only).
11. Private browsing mode (Browse doesn't have one yet; when added, coordinator should accept `isPrivate: Bool` and disable both autofill and save prompts).

## Open questions (non-blocking)

- Should "Never for this site" be reversible from somewhere other than Apple Passwords app? Needs a future settings UI.
- Should we show a small icon in the address bar when login forms are detected? Visibility cue, not essential.
- Suppress save prompt when user filled via our autofill popover with a matching credential? Already handled — the same-username-same-password no-op covers it.
