# Password Manager — Biometric Auth Before Autofill

**Date:** 2026-04-27
**Status:** Approved, implemented in same change.
**Companion:** [`2026-04-27-password-manager-design.md`](./2026-04-27-password-manager-design.md), [`2026-04-27-password-manager.md`](./2026-04-27-password-manager.md).

## Goal

Require local-device authentication (Touch ID, Apple Watch, or Mac password) every time the user accepts a credential from the autofill popover, before the password is written into the page.

## Decisions

| Item | Choice |
|---|---|
| When to prompt | Every fill. No caching. |
| API | `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)` from `LocalAuthentication`. |
| Policy | `.deviceOwnerAuthentication` (Touch ID first → Apple Watch → Mac password — system handles fallback). |
| Reason string | `"Fill saved password for <site>"`. |
| Cancel / fail | Silent no-op. Popover is already hidden by the click handler — user can re-trigger by clicking the field again. |
| Sandbox / entitlement | None needed. `LAContext` works in app-sandboxed apps. |

## Why "every fill" for v1

YAGNI. Time-based caching (1Password / Bitwarden defaults) requires:
- Tracking last-auth timestamp.
- Per-site or global policy.
- Settings UI to configure the duration.
- Bug surface around timer pause/resume across tab switches and app suspend.

None of which exist yet. Adding them later is a small follow-up. Starting from "always require" is the most secure default and the simplest correct behavior.

## Implementation

Single file changed: [`Browse/WebContent/WebViewController.swift`](../../Browse/WebContent/WebViewController.swift), in `fillCredential(_:into:)`.

```swift
import LocalAuthentication

private func fillCredential(_ cred: Credential, into form: DetectedForm) {
    guard let webView = currentWebView else { return }
    Task { @MainActor in
        let context = LAContext()
        let reason = "Fill saved password for \(cred.site)"
        let ok: Bool
        do {
            ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)
        } catch {
            ok = false
        }
        guard ok else { return }
        // ... existing JSON-encode + evaluateJavaScript fill ...
    }
}
```

The auth dialog is presented by the system on the active window. Async/await form (macOS 12+) keeps the call point clean — no completion-handler nesting.

## Non-goals (deferred)

- Time-based caching ("don't re-prompt for N minutes after last auth").
- Per-site cached unlocks.
- A settings toggle to disable auth (future preferences UI).
- Auth gate on the *save* prompt (we don't currently auth-gate writes; only reads).
- Auth gate on the autofill *popover* (popover shows freely; only the fill action is gated). This intentionally keeps the discovery experience fast.

## Open questions

- Should we also auth-gate revealing the password in the save prompt's eye-toggle? Currently the eye toggle reveals freely. Not in v1; revisit if the feature ships.
