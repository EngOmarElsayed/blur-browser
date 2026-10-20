# Passkeys and code signing

Passkeys (WebAuthn) in a `WKWebView` browser depend on one managed entitlement:

```xml
<key>com.apple.developer.web-browser.public-key-credential</key>
<true/>
```

Apple grants it per team, and it only works when a provisioning profile that
contains it signs the app. Upstream's profile ("Blur3", team `9PYC9KWKRS`)
belongs to the original author. A fork can't sign with it, which is why Google
passkey sign-in fails in fork builds.

## How signing is set up

Signing settings are no longer hard-coded in the project. They come from
`Config/Signing.xcconfig`, which the Blur-Browser target uses as its base
configuration:

| | Debug | Release |
|---|---|---|
| Entitlements | `Browse/Resources/Browse.Debug.entitlements` (no managed key) | `Browse/Resources/Browse.entitlements` (passkey key) |
| Identity | `-` (ad-hoc, "Sign to Run Locally") | `Developer ID Application` |
| Profile | none | `Blur3` |
| Team / bundle id | upstream's | upstream's |

`Signing.xcconfig` keeps upstream's values. It ends with
`#include? "Signing.local.xcconfig"`, an optional, gitignored file where a
fork sets its own team. Without that file Debug still builds, ad-hoc signed,
on any Mac.

### Use your own team

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Then edit it:

```
BLUR_DEVELOPMENT_TEAM = <your 10-character Team ID>
BLUR_BUNDLE_IDENTIFIER = com.<you>.blur-browser
BLUR_SIGN_IDENTITY_Debug = Apple Development
```

Your Team ID is the `OU=` of your certificate. This command lists it:

```bash
security find-identity -v -p codesigning
```

Check what Xcode will use:

```bash
xcodebuild -project Blur-Browser.xcodeproj -scheme Blur-Browser -configuration Debug -showBuildSettings | grep -E " (DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_IDENTITY|CODE_SIGN_ENTITLEMENTS) ="
```

Debug signs with your Apple Development certificate and needs no provisioning
profile, because `Browse.Debug.entitlements` has no restricted keys. A real
signature with a team ID matters for more than passkeys: 1Password refuses
ad-hoc-signed browsers (see [extensions.md](extensions.md)).

> Changing the bundle id gives the app a fresh `~/Library` container, so
> history, pinned tabs and website data start empty under the new id.

## Getting the passkey entitlement

Below, `<TEAM_ID>` is your Apple Developer team ID and `<BUNDLE_ID>` the bundle id you set in `Config/Signing.local.xcconfig`.

1. **Sign Xcode in to the team.** In Xcode › Settings › Accounts, add the
   Apple ID that owns team `<TEAM_ID>`. A free Personal Team can't create the
   profiles this needs.
2. **Register the App ID.** At developer.apple.com › Certificates, IDs &
   Profiles › Identifiers › **+** › App IDs › App, choose platform **macOS**
   and an **Explicit** Bundle ID of `<BUNDLE_ID>`.
3. **Request the entitlement (Account Holder only).** Open
   <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential>
   and follow its link to the dedicated request form. The general "additional
   capabilities" form is the wrong one. Other roles get an access error.
   - Team ID `<TEAM_ID>`, bundle id `<BUNDLE_ID>`.
   - Describe it as a general-purpose macOS web browser built on WebKit
     (`WKWebView`). It handles `http`/`https`, can be the default browser, and
     users sign in to arbitrary sites, so it needs WebAuthn/passkeys for any
     relying party.
4. **Wait for Apple's email.** Reports range from days to weeks.

### After the grant

1. Identifiers › `<BUNDLE_ID>` › **Capabilities** (or
   **Additional Capabilities**): turn on the web browser public key credential
   capability and save. It only appears once the grant reaches the team.
2. Register this Mac under Devices if it isn't already. The ID to enter:

   ```bash
   system_profiler SPHardwareDataType | grep "Provisioning UDID"
   ```

3. Profiles › **+** › **macOS App Development** › App ID
   `<BUNDLE_ID>` › your "Apple Development" certificate › this Mac. Name it `Blur Browser Passkeys Dev`, then
   download and double-click it. For builds you give to other people, also
   make a **Developer ID** profile; that needs a Developer ID Application
   certificate.
4. In `Config/Signing.local.xcconfig`, sign Debug with the profile and the
   managed entitlements:

   ```
   BLUR_PROFILE_Debug = Blur Browser Passkeys Dev
   BLUR_ENTITLEMENTS_Debug = Browse/Resources/Browse.entitlements
   ```

   Release, with a Developer ID profile:

   ```
   BLUR_SIGN_IDENTITY_Release = Developer ID Application
   BLUR_PROFILE_Release = <Developer ID profile name>
   BLUR_ENTITLEMENTS_Release = Browse/Resources/Browse.entitlements
   ```

5. Rebuild and check:

   ```bash
   codesign -d --entitlements - build/DerivedData/Build/Products/Debug/Blur-Browser.app
   ```

   It should list `com.apple.application-identifier`
   (`<TEAM_ID>.<BUNDLE_ID>`) and
   `com.apple.developer.web-browser.public-key-credential`. On launch the app
   logs `Passkeys enabled`:

   ```bash
   /usr/bin/log show --last 5m --predicate 'category == "Passkeys"'
   ```

6. Test at <https://webauthn.io>. Register should show the system passkey
   sheet with iCloud Keychain, "iPhone, iPad or Android device" (QR), and
   security key. Then try Google.

Nothing in code needs to change after the grant. `PasskeySupport` turns
WebAuthn back on when the running app has the entitlement.

## Before the grant: what was measured

Tested 2026-10-19 on macOS 27 with the user's Debug build and two signed
probe apps. Evidence is from `log show`.

| Build | Agent's answer | Result in the page |
|---|---|---|
| Team-signed, no provisioning profile (the normal Debug build) | "Attempted to perform authorization from process without application identifier." | `NotAllowedError` |
| Same, with WebKit's own authenticator stack (`WebAuthenticationASEnabled` off) | Same refusal: that stack goes through the same agent ("Could not connect to authorization daemon") | `NotAllowedError` |
| Signed with a Mac development profile, so it has `com.apple.application-identifier` | "Client tried to use web-browser-only options … not associated with domain webauthn.io … not properly entitled for this request. Rejecting." | `NotAllowedError` |

So in a third-party `WKWebView` app, **every** WebAuthn path goes through
AuthenticationServicesAgent and is refused without the managed entitlement:
iCloud Keychain passkeys, the phone/QR (hybrid) flow, and USB/NFC security
keys. The system sheet never appears.

- **Google's "Make sure Bluetooth is on" is misleading.** Google shows it
  whenever the WebAuthn call fails. Bluetooth is never reached. Safari has no
  `NSBluetoothAlwaysUsageDescription` either, because the hybrid flow's
  Bluetooth work happens in system daemons. The app isn't sandboxed, so
  `com.apple.security.device.bluetooth` does nothing. Info.plist now has
  `NSBluetoothAlwaysUsageDescription` anyway, for the post-grant flow in case
  macOS asks, but it doesn't change the result before the grant.
- **What the app does now:** `Browse/WebContent/PasskeySupport.swift` checks
  the running app's signature. Without the entitlement it turns off WebKit's
  `WebAuthenticationEnabled` and installs Blur-Browser's own CTAP2 client for
  USB security keys instead (see [Security keys without the
  entitlement](#security-keys-without-the-entitlement)). The app logs
  `Passkeys disabled: missing …` once at launch.
- **Associated domains don't help a browser.** With an application
  identifier, the agent would accept a site only if the app listed it under
  `webcredentials:` and the site's `apple-app-site-association` file named
  the app. That's impossible for arbitrary sites like Google.
- **Real alternatives, not built:**
  - CTAP2 over USB HID, done ourselves: now built, see below.
  - The phone/QR flow would also need caBLE v2 (BLE advertising, a tunnel
    service, and the Noise handshake), which is much larger.
  - `ASWebAuthenticationSession` runs Safari's stack, but its cookies land in
    Safari's store, so the tab doesn't come out signed in.

## Security keys without the entitlement

`Browse/WebContent/SecurityKeys/` talks to USB FIDO2 keys directly, the way
Chrome and Firefox do on macOS, so YubiKeys and similar keys work before
Apple grants the entitlement. It's only installed when
`PasskeySupport.isAvailable` is false; with the entitlement WebKit's native
WebAuthn is left alone.

| File | Role |
|---|---|
| `Browse/JS/securityKeyShim.js` | `navigator.credentials` + `PublicKeyCredential` for the page world of every frame, posting to the `blurSecurityKey` handler |
| `SecurityKeyBridge.swift` | Message handler with reply. Takes the origin from `WKFrameInfo.securityOrigin`, applies the timeout, AbortSignal and one-request-per-window rules |
| `WebAuthnOrigin.swift` | HTTPS (or localhost) only, no IP addresses, rpId must be the host or a registrable suffix, appid check, clientDataJSON |
| `WebAuthnOptions.swift` | Parses the options, COSE → SPKI for `getPublicKey()` |
| `SecurityKeyRequest.swift` | create()/get(): pick a key, PIN or fingerprint, makeCredential/getAssertion, account choice |
| `CTAP2.swift` | CTAP2 commands and PIN/UV auth protocols 1 and 2 (ECDH P-256 via CryptoKit, AES-256-CBC via CommonCrypto) |
| `CTAPHID.swift` | CTAPHID framing over IOKit HID, usage page `0xF1D0` |
| `CBOR.swift` | The CBOR subset CTAP2 needs, canonical map order |
| `SecurityKeySheet.swift` | The AppKit sheet: insert/touch, PIN, new PIN, account choice, errors |

Behaviour worth knowing:

- **User activation.** If the call doesn't follow a click or key press
  (within 10 s, or `navigator.userActivation.isActive`), the sheet first asks
  "Use a security key?" instead of rejecting, since sites like Google start
  the key prompt on page load. The key still needs a touch either way.
- **Extensions.** When any web extension is installed, WebKit's WebAuthn
  stays on so password managers that wrap `navigator.credentials` (1Password
  only installs its wrapper if it exists) can. The shim then wraps WebKit's
  `create`/`get` and `PublicKeyCredential` members instead of replacing
  them, so an extension that runs later and declines a request falls back to
  the security key path. An extension that replaced them first is left alone.
- **Cross-origin iframes** may call `get()` (clientDataJSON then carries
  `crossOrigin: true` and `topOrigin`) but not `create()`, because the
  frame's permissions policy isn't visible to the app.
- **appid** (U2F-era registrations, used by Google): the key is probed
  silently (`up: false`) under the rpId and then the appid; the one that
  holds the credential is used and `getClientExtensionResults().appid` says
  which.
- **Attestation** `none` (the default) is replaced with `fmt: "none"`; the
  AAGUID is kept.
- **The public suffix check** is a built-in list (every TLD plus common
  multi-label and hosting suffixes); macOS has no public API for the PSL.
- **Not supported:** U2F-only keys (no CTAP2), NFC/BLE, the phone/QR
  (hybrid) flow, iCloud Keychain passkeys, conditional mediation (autofill
  UI; such calls stay pending until aborted), and the `prf`, `hmac-secret`
  and `largeBlob` extensions.

Logs: `/usr/bin/log show --last 5m --predicate 'category == "SecurityKeys"'`.
