# Password Manager — HTTP Auth Dialog Support

**Date:** 2026-05-03
**Status:** Approved, ready for implementation.
**Companion docs:**
- [`2026-04-27-password-manager-design.md`](./2026-04-27-password-manager-design.md) — base password manager design
- [`2026-04-27-password-manager-biometric-auth-design.md`](./2026-04-27-password-manager-biometric-auth-design.md) — biometric auth before fill

## Goal

Make the password manager work for HTTP Basic and HTTP Digest authentication dialogs the same way it works for HTML form logins. Concretely:

1. **Autofill.** When the existing `AuthenticationDialogView` modal appears for a site that has saved credentials, the autofill popover anchors to the dialog's username field (just like form fields). Click a credential → Touch ID → both fields fill.
2. **Save on success.** When the user submits credentials in the dialog and the request succeeds, the same `SavePromptOverlay` that lands at the top-left after a form login appears, offering Save / Update / Never.

Verified motivation: Klivvr's dev API docs (e.g. `https://harrison.dev.klivvrservices.com/api/v2/docs/`) and similar `.htaccess`-style protected staging servers use HTTP Basic auth and are currently invisible to the password manager.

## Decisions

All decisions are "same as the existing form-based flow" unless noted.

| Item | Choice | Rationale |
|---|---|---|
| Autofill UX | Reuse existing `AutofillPopoverPanel` anchored to the dialog's username field | Visual + interaction parity with form-based autofill. User asked for "same as already implemented." |
| Multiple credentials | Existing popover lists them, user picks | Same as form path. |
| Touch ID gate | Same `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)` | Identical to `WebViewController.fillCredential(_:into:)`. |
| Save UX | Same `SavePromptOverlay` at top-left, same Save / Update / Never / Skip buttons | No new UI components. |
| Save trigger | Use the existing decision matrix on a fresh entry point — record the submission at dialog-completion time, fire the matrix on the next `WKNavigationDelegate.webView(_:didFinish:)` | Form path uses `scriptReady` for the same purpose; HTTP auth uses `didFinish` because the URL doesn't necessarily change after Basic auth (the protected page just loads). |
| Site key | `SiteIdentity.key(for: webView.url)` (eTLD+1, HTTPS-only) | Same as forms. HTTP-only sites refused (Basic over HTTP transmits credentials in cleartext base64 — refusing is correct). |
| Realm scoping | Host-only (eTLD+1). Realm ignored. | YAGNI. Multi-realm hosts are rare; existing `Credential` schema unchanged. |
| Failure detection | A subsequent challenge for the same protection space invalidates the pending submission | Mirrors the JS-side "loginInconclusive" idea. |
| TTL | 30 seconds on the pending auth submission | Slightly longer than the form path's 10 s because HTTP auth flows have no JS watchdog and the page can take longer to render. |

## Architecture

The whole change is small and additive:

- **`AuthenticationDialogView`** gains three thin affordances: a focus callback, a screen-rect accessor for its username field, and a programmatic `fill(username:password:)` method. No layout or styling changes.
- **`PasswordManagerCoordinator`** gains a separate `pendingAuthSubmission` slot (parallel to `lastSubmissionByUnit`) and two methods: `recordAuthSubmission(...)` and `noteAuthSubmissionFinished()`. The save-decision matrix is extracted from `handleSuccess` into a private `captureCredential(site:username:password:)` helper that both paths call.
- **`WebViewController.showAuthenticationDialog(host:realm:completion:)`** wires the dialog's username-focus callback to the existing `autofillPanel`, and on row-selection runs the same Touch ID flow as form fills before calling `dialog.fill(...)`.
- **`WebViewCoordinator`** gets two one-line additions: at the existing dialog completion, before building the `URLCredential`, call `recordAuthSubmission`; in `webView(_:didFinish:)`, call `noteAuthSubmissionFinished`.

Files added: 0. Files modified: 4 (`AuthenticationDialogView.swift`, `PasswordManagerCoordinator.swift`, `WebViewController.swift`, `WebViewCoordinator.swift`).

## Components

### `PasswordManagerCoordinator`

Refactor `handleSuccess` to extract its body into a shared helper:

```swift
private func captureCredential(site: String, username: String, password: String) {
    if blocklistStore.contains(site) { return }
    let existing = passwordStore.lookup(forSite: site)
    if existing.contains(where: { $0.username == username && $0.password == password }) { return }
    if let match = existing.first(where: { $0.username == username }) {
        setPendingSaveCredential(.update(site: site,
                                         username: username,
                                         password: password,
                                         existingId: match.id))
    } else {
        setPendingSaveCredential(.save(site: site,
                                       username: username,
                                       password: password))
    }
}
```

`handleSuccess(unitId:)` becomes:

```swift
private func handleSuccess(unitId: String) {
    guard let payload = lastSubmissionByUnit.removeValue(forKey: unitId) else { return }
    guard let url = webView?.url, let site = SiteIdentity.key(for: url) else { return }
    captureCredential(site: site, username: payload.username, password: payload.password)
}
```

Add the HTTP-auth path:

```swift
private struct PendingAuthSubmission {
    let site: String
    let username: String
    let password: String
    let capturedAt: Date
}
private var pendingAuthSubmission: PendingAuthSubmission?
private let authSubmissionTTL: TimeInterval = 30

func recordAuthSubmission(username: String, password: String, url: URL) {
    guard let site = SiteIdentity.key(for: url) else {
        pendingAuthSubmission = nil
        return
    }
    pendingAuthSubmission = PendingAuthSubmission(
        site: site, username: username, password: password, capturedAt: Date()
    )
}

func noteAuthSubmissionFinished() {
    guard let pending = pendingAuthSubmission else { return }
    pendingAuthSubmission = nil
    guard Date().timeIntervalSince(pending.capturedAt) < authSubmissionTTL else { return }
    captureCredential(site: pending.site,
                      username: pending.username,
                      password: pending.password)
}

func discardPendingAuthSubmission() {
    pendingAuthSubmission = nil
}
```

### `AuthenticationDialogView`

Three additions:

```swift
var onUsernameFieldFocused: (() -> Void)?

var usernameFieldScreenRect: CGRect {
    guard let window = window else { return .zero }
    let rectInDialog = convert(usernameField.frame, from: usernameField.superview)
    let rectInWindow = convert(rectInDialog, to: nil)
    return window.convertToScreen(rectInWindow)
}

func fill(username: String, password: String) {
    usernameField.stringValue = username
    passwordField.stringValue = password
    // Match the existing dialog's expected text-changed handling so Submit becomes
    // enabled if it was disabled while empty.
    NotificationCenter.default.post(name: NSControl.textDidChangeNotification,
                                    object: usernameField)
    NotificationCenter.default.post(name: NSControl.textDidChangeNotification,
                                    object: passwordField)
}
```

The focus callback fires when the username field starts editing. Either:
- Implement `NSTextFieldDelegate.controlTextDidBeginEditing(_:)` and forward, or
- Observe `NSControl.textDidBeginEditingNotification` for the field.

Either works; pick whichever fits the existing `AuthenticationDialogView` style.

### `WebViewController.showAuthenticationDialog`

After creating the dialog and before adding it to the view hierarchy, install:

```swift
dialog.onUsernameFieldFocused = { [weak self, weak dialog] in
    guard let self,
          let dialog,
          let url = self.currentWebView?.url,
          let site = SiteIdentity.key(for: url) else { return }
    let creds = self.passwordStore.lookup(forSite: site)
    guard !creds.isEmpty,
          let window = dialog.window else { return }
    let rect = dialog.usernameFieldScreenRect
    self.autofillPanel.show(below: rect, in: window, credentials: creds) { [weak self, weak dialog] cred in
        guard let self, let dialog else { return }
        Task { @MainActor in
            await self.fillAuthDialog(dialog, with: cred)
        }
    }
}
```

`fillAuthDialog`:

```swift
private func fillAuthDialog(_ dialog: AuthenticationDialogView, with cred: Credential) async {
    let context = LAContext()
    let reason = "Fill saved password for \(cred.site)"
    let ok: Bool
    do {
        ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    } catch {
        ok = false
    }
    guard ok else { return }
    dialog.fill(username: cred.username, password: cred.password)
}
```

### `WebViewCoordinator`

Two additions to the existing file:

**Inside the auth-dialog completion (existing site):**

```swift
self.viewController?.showAuthenticationDialog(host: host, realm: realm) { username, password in
    if let username, let password {
        if let url = webView.url {
            self.viewController?.passwordCoordinator?.recordAuthSubmission(
                username: username, password: password, url: url
            )
        }
        let credential = URLCredential(user: username,
                                       password: password,
                                       persistence: .forSession)
        completionHandler(.useCredential, credential)
    } else {
        self.viewController?.passwordCoordinator?.discardPendingAuthSubmission()
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
```

**On `webView(_:didFinish:)`** — add a one-line call at the start (or in whichever existing implementation handles successful navigations):

```swift
viewController?.passwordCoordinator?.noteAuthSubmissionFinished()
```

If a fresh challenge for the same host arrives with `previousFailureCount > 0` before `didFinish` lands, also discard:

```swift
if challenge.previousFailureCount > 0 {
    self.viewController?.passwordCoordinator?.discardPendingAuthSubmission()
}
```

(Inserted at the start of the Basic/Digest branch, before the `>= 3` cancel.)

## Data flow

### Autofill

1. WKWebView receives 401 from server → `WKNavigationDelegate.didReceive` fires.
2. `WebViewCoordinator` invokes `WebViewController.showAuthenticationDialog`.
3. `AuthenticationDialogView` is added to the view hierarchy. macOS makes its username field the first responder, which fires `textDidBeginEditingNotification`.
4. `WebViewController`'s focus callback runs → `passwordStore.lookup(forSite:)` → `autofillPanel.show(...)`.
5. User clicks a credential row → `LAContext.evaluatePolicy` → on success, `dialog.fill(username:password:)`.
6. User clicks Submit → existing dialog `onSubmit` callback returns the credentials to `WebViewCoordinator`'s completion → `URLCredential` → WebKit retries.

### Save

1. Same setup; user submits credentials (typed manually or via autofill).
2. `WebViewCoordinator`'s completion calls `passwordCoordinator.recordAuthSubmission(...)` before passing the credential to WebKit.
3. WebKit retries the request with the credential. Two outcomes:
   - **Success (page loads):** `webView(_:didFinish:)` fires → `noteAuthSubmissionFinished()` → `captureCredential(...)` → existing decision matrix → `SavePromptOverlay` appears at top-left.
   - **Failure (401 again):** `didReceive` fires again with `previousFailureCount > 0` → `discardPendingAuthSubmission()` → no save prompt.

## Edge cases

| Case | Behavior |
|---|---|
| HTTP-only host | `SiteIdentity.key` returns nil → no autofill, no save (Basic over HTTP is cleartext-equivalent). |
| User cancels dialog | `discardPendingAuthSubmission()` keeps state clean; existing cancel logic unchanged. |
| User cancels Touch ID for autofill | Popover hides, dialog stays focused on username; user types or re-clicks a row. |
| Multiple challenges in a single load (failed first attempt) | Each successful submit overwrites `pendingAuthSubmission`. Only the last submitted creds get saved. |
| Page redirects after auth | `noteAuthSubmissionFinished` fires on the next `didFinish` (within 30 s). Site comparison is via eTLD+1 so cross-subdomain redirects on the same site are fine. |
| Same username + same password as already saved | Existing no-op rule in `captureCredential` fires — no prompt. |
| User refocuses username field while popover is open | Existing popover dedup applies. |
| Auth success but the page itself contains a form login | Form path and HTTP auth path are mutually exclusive at the moment of capture; both would converge on `setPendingSaveCredential`, and it's idempotent for same-cred no-ops. |

## Non-goals (deferred)

- **Realm-scoped credentials.** All saved entries are eTLD+1-keyed. A site that uses different realms for "Admin" vs "Reports" gets one shared credential.
- **Auto-arming Touch ID** when the dialog appears (i.e., showing the system Touch ID prompt without waiting for a row click). User explicitly rejected this for the form-based flow; not adding it here either.
- **HTTP Negotiate / NTLM / client-cert prompts.** Out of scope for v1; the only Basic and Digest paths are wired.
- **Saving credentials submitted on plain HTTP.** Refused, as above.
- **Editing realm or other auth-protectionSpace metadata in the save prompt.** The existing `SavePromptView` only edits username and password; that's enough.

## Testing

No new unit tests (project has no XCTest target — manual verification only, consistent with the rest of the password manager).

Manual verification matrix:

| Scenario | Site | Expected |
|---|---|---|
| Save first time | `https://harrison.dev.klivvrservices.com/api/v2/docs/` | Dialog appears → user types creds → Submit → page loads → Save prompt at top-left → Save → entry appears in macOS Passwords app as `Browse — klivvrservices.com`. |
| Autofill on next visit | Same URL, fresh session | Dialog appears → click into username field → autofill popover lists the saved cred → click row → Touch ID → both fields fill → Submit → page loads. |
| Wrong password | Same URL, intentionally wrong creds | Dialog appears → Submit → 401 → dialog reappears with `previousFailureCount=1` → no save prompt. Pending submission discarded. |
| Cancel dialog | Same URL, click Cancel | No save prompt; page navigates to error or stays. |
| HTTP-only site | Any `http://`-protected page | No autofill popover; even after successful auth, no save prompt. |
| Multiple credentials | Save two creds for the same site (e.g., personal + work intranet) | Popover lists both; selecting one fills correctly. |
| Same creds as saved (re-login) | Already-saved cred | Submit → page loads → no prompt (same-username-same-password no-op). |

---

If anything is off, the design doc is the authoritative spec; revise here before code.
