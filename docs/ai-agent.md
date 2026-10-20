# AI browsing agent

The browser's one AI pane, on the right. It drives navigation and browsing with
tool-capable models, and works as page-aware chat with models that can't call tools.
Open it with **⌥⌘A** (View → Toggle Agent) or the sparkles button in the toolbar.

It replaces the separate Assistant pane (⌘⇧Y) from `feat/native-assistant`. That
pane's providers are now `ModelProvider`s, its settings moved to Settings → AI, and
its API keys moved into the Keychain (see "Migration from the Assistant pane").

## Pieces

| Area | Files |
|---|---|
| Panel (right side, shares the edge with History) | `Browse/Agent/Views/AgentPanelView.swift`, hosted in `MainSplitViewController` |
| Agent loop | `Browse/Agent/AgentController.swift` |
| Tools over `TabManager` / `WKWebView` | `Browse/Agent/Tools/AgentTools.swift`, `AgentTools+Actions.swift` (click, type, scroll) |
| Virtual cursor and real input | `Browse/Agent/Pointer/AgentActionOverlay.swift`, `AgentInputDriver.swift`; hosted by `WebViewController` |
| Permission model + consent log | `Browse/Agent/Permissions/AgentPermissions.swift` |
| Model providers | `Browse/Agent/Provider/` (`ModelProvider` protocol, `ClaudeProvider`, `OpenAICompatibleProvider`, `GeminiProvider`, `AIProviderStore`, `KeychainStore`) |
| Local-network relay | `tools/relay.py` |
| Saved chats (encryption, Touch ID lock) | `Browse/Agent/Conversations/` (`AgentConversation`, `AgentConversationVault`, `AgentConversationKey`), `Browse/Agent/Views/AgentConversationsView.swift` |
| Settings → AI | `Browse/Settings/AISettingsView.swift` |

## Tools and risk levels

Every tool declares a risk level. The level decides whether it needs approval.

| Risk | Tools | Asks in Ask mode? |
|---|---|---|
| Read-only | `list_tabs`, `read_page`, `scroll` | Never |
| Navigation | `open_url`, `new_tab`, `switch_tab`, `go_back`, `go_forward` | Yes |
| Page-mutating | `click`, `type_text` | Yes |
| Form-submit | `type_text` with `submit: true`; `click` on a submit button | Yes |

A tool's risk can only go up at runtime. Before asking, `click` checks the target
element, and a submit button (`<button>` in a form, `input[type=submit|image]`) makes it
**form-submit**. That way, allowing clicks on a site doesn't also allow submitting
forms there.

`scroll` counts as read-only. It changes only the viewport, sends nothing, and the
agent needs it to read long pages.

Other limits that apply in every mode:

- `open_url` and `new_tab` load only `http`/`https`. Anything without a scheme becomes
  `https://…` or a search, so `file://` and `javascript:` can't be opened.
- `type_text` refuses password fields. `read_page` lists what each field is for (label
  or placeholder), never what's typed in it.
- Page scripts run in WebKit's isolated `.defaultClient` content world, so page
  JavaScript can't change the agent's helpers.
- The page text is labelled as untrusted in the tool result. The system prompt tells
  the model to treat it as data, not instructions.
- `read_page` and element lookup also look inside open shadow roots, in document order,
  because sites like Reddit put their search field inside web components.
- The loop stops after 30 model steps. **Stop** cancels the run, and any approval it's
  waiting on counts as a denial.

## How actions look: virtual cursor and real input

The agent still picks **which** element to act on from `read_page`'s numbered list.
What changed is how `click`, `type_text` and `scroll` are shown and delivered.

1. **Aim.** A script in the isolated content world scrolls the element into view,
   smoothly when animation is on. It returns the centre of the element's visible part
   in CSS viewport coordinates, and whether a click there would land on it.
   `elementFromPoint` is checked through shadow roots, and a `<label>` for the field
   counts.
2. **Show.** `AgentActionOverlay` sits above everything in the page card. It draws an
   arrow cursor in the theme accent, which glides there over about 300–500 ms
   (ease-in-out, longer for longer trips), then a ripple for a click. A small label
   says "Agent is clicking…", "…typing…", "…submitting…" or "…scrolling…". Coordinates
   are converted CSS px → web view points using `bounds.width / innerWidth`, which
   covers page zoom.
3. **Deliver.**
   - Clicks are `mouseMoved`, `leftMouseDown` and `leftMouseUp` `NSEvent`s handed
     straight to the `WKWebView`.
   - Typing first clicks the field the same way. It then selects the field's contents
     so typing replaces them, and sends one keyDown/keyUp per character. Delays are
     45–120 ms × speed, with US key codes and Shift where needed.
   - Submitting is a real Return.
   - Pages get `isTrusted` events, just as from the user. Nothing goes through the
     window's event queue, so the **real system cursor never moves**.
4. **Block the user, briefly.** While an action runs, the overlay swallows mouse
   clicks and scrolling over the page, without dimming it, so a stray click can't
   race the agent. The overlay is transparent to hit-testing the rest of the time.

### Fallbacks and safety checks

- **Click.** If the point is covered or inside a cross-origin iframe, or a probe sees
  no trusted click arrive, it falls back to the old scripted `el.click()`. The probe
  checks `composedPath()` within 150 ms. A navigation counts as delivered.
- **Typing.** Before **every** keystroke, it checks that focus is still on the target
  and isn't a password field. If focus moved, it stops sending keys.
  - If no trusted keydown reached the field, the whole value and the submit go
    through the old script path.
  - If keys arrived but the text differs (other keyboard layouts, input methods), the
    value is corrected by script. Only a yes/no comes back, never the field's value.
- **Password fields.** These are still refused before any input happens.
- **Permissions.** Ask and Dangerous are unchanged. `AgentSession.decide` runs before
  a tool's `run`, and the cursor only changes how an approved action is carried out.

### Settings → AI → Agent actions

- **Animate agent actions** (`ai.animateActions`, on by default). Off: no cursor and
  no ripple, and typing goes at about 8 ms per key. Actions are still real
  clicks and keystrokes, and still block the mouse while they run.
- **Speed**: Slow (×1.7), Normal, or Fast (×0.45) for cursor travel and typing
  (`ai.actionSpeed`).

## Permission modes

The mode belongs to the window. `AgentSession` lives on `BrowserWindowController` and
is never saved, so both modes reset on relaunch and one window's mode never affects
another.

### Ask (default)

- Read-only actions run without asking.
- Any other action shows an inline card with **Allow**, **Allow on ‹host›** and
  **Deny**.
  - **Allow** runs this one action.
  - **Allow on ‹host›** adds a grant for that host at that risk level, for this window
    session. Later actions on the host at that level or lower run without asking. A
    riskier action still asks: a navigation grant doesn't cover clicks, and a click
    grant doesn't cover form submission.
  - **Deny** returns an error to the model. It is told not to retry and to ask the
    user what to do instead.
- The host is the current tab's host for page actions, and the destination host for
  `open_url`, `new_tab` and `switch_tab`.

### Dangerous — never ask

- Every action runs without a prompt, in this window only.
- The **only** way in is the mode menu in the panel header, which opens a consent
  sheet. **Turn On** stays disabled until the user ticks the acknowledgement.
- `AgentSession.enableDangerousMode` writes the consent record first and switches the
  mode only if the write succeeded. Nothing else changes the mode to `.dangerous`.
- While it's on, a red **Dangerous** capsule shows in the toolbar next to the URL
  field, the panel shows a red banner with **Stop**, and the sparkles button turns
  red.
- To leave, switch back to Ask in the panel menu, press **Stop** on the banner, or
  quit. Switching back is logged too.

### Consent log

`~/Library/Application Support/Blur-Browser/agent-consent-log.jsonl` is append-only
JSON Lines. The file is created with mode 0600, and the app only appends to it. It
never rewrites or truncates it. Each line looks like this:

```json
{"acknowledgement":"I understand the agent will …","appVersion":"0.9.2","event":"dangerous_mode_enabled","mode":"dangerous","timestamp":"2026-10-19T17:21:43Z","windowSessionID":"95FBF432-…"}
```

`event` is `dangerous_mode_enabled` or `dangerous_mode_disabled`. `windowSessionID` is
the `AgentSession.id` of the window. **Settings → AI → Show in Finder** opens the file.

## Model providers

`ModelProvider` takes a system prompt, a provider-neutral transcript (`AgentMessage` /
`AgentContentBlock`), the tool definitions and a stream callback, and returns the next
assistant turn. Wire formats stay inside each provider. Everything is plain URLSession,
since the project takes no third-party dependencies.

| Kind | Provider | Endpoint | Tools | Streaming |
|---|---|---|---|---|
| Anthropic | `ClaudeProvider` | `POST {base}/messages` | Yes | No |
| OpenAI-compatible | `OpenAICompatibleProvider` | `POST {base}/chat/completions` (SSE) | `tools` / `tool_calls`, if enabled | Yes |
| Google Gemini | `GeminiProvider` | `POST {base}/models/{model}:streamGenerateContent?alt=sse` | `functionDeclarations`, if enabled | Yes |

"OpenAI-compatible" covers OpenAI itself and local servers: llama.cpp, vLLM, LM
Studio, Ollama, or the loopback relay below.

### Configuring providers (Settings → AI)

- `AIProviderStore` holds the list of providers and which one is active. It's saved in
  UserDefaults (`ai.providers`, `ai.activeProviderID`) and holds **no secrets**.
- Each provider has a name, type, base URL, model, a **Browser tools** switch and an
  API key. The radio button picks the active one. The pane header also has a provider
  menu for switching quickly.
- Defaults on a fresh install: Claude (`claude-opus-5-5`), OpenAI (`gpt-4.1-mini`),
  Google Gemini (`gemini-2.5-flash`) and a "Local model" at `http://127.0.0.1:8080/v1`.
- Keys are Keychain generic passwords: service `Blur-Browser.AI`,
  `WhenUnlockedThisDeviceOnly`. The built-in Claude entry uses account
  `anthropic-api-key`, as the first agent release did, so a saved key keeps working.
  Others use `provider-‹uuid›`. Deleting a provider deletes its key.
- Loopback and private-network base URLs (`localhost`, `127.x`, `10.x`, `172.16–31.x`,
  `192.168.x`, `*.local`) don't need a key. Hosted ones do.

### Browser tools on or off

With **Browser tools** on, the model gets the tools above and the permission modes
apply. With it off, the provider is chat-only: the pane hides the Ask/Dangerous menu,
shows an **Include this page** checkbox, and when it's ticked attaches the current
tab's `read_page` output to each message, labelled as untrusted. Previous tool calls
in the conversation are sent as plain text, because many servers reject `tool_calls`
in a request without `tools`.

Hosted APIs start with tools on. Local endpoints start with tools off, since tool
calling depends on the server (llama.cpp needs `--jinja`, vLLM needs a tool parser).
Turn it on if yours supports it.

### Provider notes

- **Claude.** The default model is `claude-opus-5-5`, with
  `output_config.effort: "medium"`. Effort is only sent for the 5.x models, so older
  model ids imported from the Assistant pane still work. Server-side refusal fallback
  (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`) is on for the
  models that support it, and only against `api.anthropic.com`.
- **Transcript.** The transcript is append-only. Assistant turns are stored exactly as
  returned. Every `tool_use` gets a `tool_result`, even when the run is cancelled.
- **Opaque blocks.** Provider-specific data is kept as `.opaque(vendor:)` and sent
  back unchanged. For Claude these are `thinking` blocks. For Gemini, the whole model
  turn is kept so `thoughtSignature`s go back intact. Other providers skip blocks
  from a different vendor, so you can switch models mid-conversation.
- **Gemini schemas.** Gemini takes an OpenAPI subset, so `additionalProperties` and
  empty `required` are removed, and tools with no parameters send no `parameters`.
  `functionResponse` gets the function name from the matching call.
- **Streaming.** OpenAI-compatible and Gemini responses stream into the pane. Reasoning
  is shown dimmed while the answer hasn't started: `reasoning_content`/`reasoning`
  deltas, Gemini `thought` parts, and `<think>…</think>` in the content. If the content
  only has a closing `</think>`, because the chat template opened it in the prompt,
  everything before it counts as reasoning.

To add a provider, conform to `ModelProvider`, add an `AIProviderKind` case and build
it in `AIProviderConfig.makeProvider()`.

### Migration from the Assistant pane

The Assistant pane kept providers **and API keys in plain text** in
`~/Library/Application Support/Blur-Browser/assistant.json`. On first launch,
`AIProviderStore` migrates them once:

1. Each provider is imported with the same id, name, URL and model.
2. Each non-empty key is saved to the Keychain.
3. An Anthropic entry's key goes to the built-in Claude entry if that has no key yet,
   so no duplicate is added. Otherwise it becomes its own entry.
4. Imported entries replace stock entries without a key that have the same endpoint.
5. The Assistant pane's active provider becomes the active one.
6. Only after **every** key is stored, `assistant.json` is deleted and
   `ai.migratedAssistantJSON` is set. If any Keychain write fails, nothing is
   committed and the migration runs again on the next launch.

The migration doesn't touch backups such as `assistant.json.bak`. Delete those by hand,
since they may contain keys.

### Local models

macOS Local Network privacy can block the app from reaching `192.168.x.x`. The failure
shows up as `NSURLErrorDomain -1009` with `Local network prohibited` in `log show`.
`NSLocalNetworkUsageDescription` is set in `Info.plist`, so macOS should ask on the
first request. If it doesn't, go to **System Settings → Privacy & Security → Local
Network → Blur-Browser**, turn it on, and relaunch. Unsigned builds may never be
allowed. In that case, run the loopback relay (loopback is never gated) and point the
provider at it:

```bash
python3 tools/relay.py --listen 127.0.0.1:18080 --target 192.168.1.150:8080
# base URL: http://127.0.0.1:18080/v1
```

`Info.plist` sets `NSAllowsArbitraryLoads`, so URLSession can reach `http://` model
servers on any host. Web content is still loaded by WebKit.

### Debug-only scripted provider

Debug builds launched with `BLUR_AGENT_PROVIDER=scripted` use `ScriptedProvider`. It
handles one request, "open ‹domain› and tell me the heading", with no API key, so you
can test the loop, tools and approval cards. Any other message gets a plain reply saying
how many of your messages it can see, which is handy for checking that a saved chat
continued. It isn't compiled into Release builds.

`BLUR_AGENT_AUTOSEND="…"` (Debug only) sends one message about three seconds after
launch, after saved chats auto-unlock. To test persistence without Touch ID, pass
`-ai.chats.requireTouchID NO` as a launch argument; it applies to that run only and is
never written to disk.

## Saved chats

Agent chats are saved so you can pick one up later, encrypted on this Mac, and locked
behind Touch ID.

- **What's saved.** One file per chat: id, title (the first message, or your rename),
  created and updated dates, the provider and model it last ran with, the transcript
  sent to the model, and the rows the pane shows. Saves are debounced (1 s) and also
  happen when a run ends, when you switch chats, on window close, on quit and before
  locking.
- **What isn't.** Page text attached by "Include this page" is replaced with a short
  stub. Tool results such as `read_page` output are cut to 1,500 characters. Streaming
  rows, pending approvals and running tool calls aren't kept: an unfinished action is
  saved as interrupted, and a dangling tool call gets an "interrupted" result so the
  chat can continue. Dangerous mode and site grants stay per window session; opening a
  saved chat switches the window back to Ask.
- **Where.** `~/Library/Application Support/Blur-Browser/AgentConversations/<uuid>.chat`
  (folder 0700, files 0600). Each file is `BLURCHAT` followed by an AES-256-GCM sealed
  box of the JSON, with `blur-agent-chat:<uuid>` as associated data so files can't be
  swapped. There's no plaintext index: titles and dates live inside each encrypted file
  and are decrypted into memory only while unlocked. The file names (random UUIDs),
  sizes and modification times are visible.
- **The key.** A random 256-bit key, made on first unlock and kept in the Keychain
  (service `Blur-Browser.AgentConversations`, account `conversation-key`, this device
  only, not synced). It's never written to disk or logged. Settings → AI → Saved chats
  shows which mode below is in effect.
- **Pane.** The clock button in the header lists saved chats (switch, rename, delete,
  Lock). New Conversation starts a fresh chat and keeps the old ones. When locked, the
  pane shows "Unlock with Touch ID". On launch, the first window reopens the most
  recent chat once unlocked. If a chat last ran on a different model than the one
  selected now, a small notice above the composer says so; it continues with the
  selected provider.

### Touch ID and the Keychain

Unlocking runs `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`: Touch ID, with
your Mac password as a fallback. Chats lock again after the "Lock after" time in the
background or idle (default 15 minutes; idle is system-wide input), and always when the
Mac sleeps, the display sleeps, the screen locks or you switch users. Locking saves,
then drops the key and every decrypted chat from memory. Turning the Touch ID
requirement off asks for Touch ID first.

The app first tries to bind the key itself to user presence: a data-protection Keychain
item with a `.userPresence` `SecAccessControl`, so macOS won't release it without
Touch ID or the password. That Keychain needs an `application-identifier` entitlement
from a provisioning profile. The current fork builds (Apple Development certificate,
team 95B9YTC3G2, no profile) don't have one: `SecItemAdd` returns `errSecMissingEntitlement`
(-34018), which was checked with a binary signed the same way. **So with today's signing,
the fallback is in effect:** the key is a normal login-Keychain item that only this
app's signature can read without a prompt, and the Touch ID gate is enforced by the app
before it reads the key. If the build is later signed with a profile, the same code
stores new keys biometry-bound automatically; nothing else changes.

### Threat model

Protects against:
- Someone reading the files: another user account, a backup or Time Machine
  snapshot, a copied home folder, cloud sync of Application Support, or a tool that
  scans your disk. Without the Keychain key the files are ciphertext, and tampering
  with them is detected (GCM authentication).
- Someone at your unlocked Mac who opens the browser after it's been idle, asleep or
  locked: they get the lock screen, not your chats, unless they pass Touch ID or know
  your password.

Doesn't protect against:
- **Model providers.** Everything you send, including page text from "Include this
  page" and `read_page`, goes to the provider you selected (or your local model and
  relay) in the clear over its API. Saving chats doesn't change what they see or keep.
- Malware running as you while your Mac is unlocked. It can read the login Keychain
  item or the app's memory while chats are unlocked. In the fallback mode Touch ID is
  an app-level gate, not a Keychain one.
- Someone who knows your Mac password; it's the Touch ID fallback.
- Metadata: how many chats exist, their sizes and when they changed.
- Copies outside these files: anything you copied out, and what macOS or WebKit
  caches about the pages themselves (history, cache). The agent pane doesn't log chat
  text.

## Not in this slice

- Streaming for Claude (it uses the non-streaming Messages API).
- Element targeting inside iframes and closed shadow roots. `read_page` sees the top
  document and its open shadow roots only.
- Real scroll-wheel events. `scroll` moves the cursor to the page centre and scrolls by
  script, smoothly when animation is on.
- Hover menus. The cursor sends one `mouseMoved` at the target, not a continuous path.
- Per-site grants that outlive the window session, and a settings list for revoking
  grants mid-session. Closing the window clears them.
- Custom system prompt and temperature, which the Assistant pane had. Its stored
  values aren't migrated. Each mode uses a built-in prompt and the provider's default
  temperature.
