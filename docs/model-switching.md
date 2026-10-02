# Direct model switching and Web Deck in 0.6.0

Status: **internal integration; working 0.3.1 switching confirmed by the user**
on Codex 26.928.31416 (2026-10-02). Version 0.6.0 adds a paired-phone Web Deck to
the existing five presets, legacy JSON migration, and optional startup connection.
Its new remote path is fixture-tested, not verified against live Codex by the agent. The implementation is independently
written; no original Codex bundle code is redistributed.

## Runtime path

1. The user chooses **Enable Direct Switching…** and clicks the restart button.
   Codex is relaunched with remote debugging bound to `127.0.0.1` on an available port.
2. A preset uses the Chromium DevTools Protocol (CDP) to identify one main window.
   Swift rejects a WebSocket address outside the configured loopback endpoint.
3. The packaged `apply-preset.js` finds visible model controls and maps their
   DOM host nodes to the committed React tree. It selects one visible composer
   and its existing model-selection dispatcher, ignoring hidden picker surfaces.
4. It resolves the configured model against the live catalog, checks supported
   effort and disabled state, and invokes the existing callback so Codex retains
   its own model confirmation and permission handling.
5. It reads back the composer selection, requiring the exact model and effort
   to remain stable before returning success. Focus, route, or composer identity
   changes stop verification.

This avoids model-menu clicks and synthetic input. It needs no Accessibility
permission. Existing-chat selection follows Codex's native settings update path;
new drafts use their bound composer callback. It affects subsequent turns and
does not restart an active answer. A failure after invoking the callback may
leave an applied change, so users must inspect the selection before sending.

The underlying existing-chat path includes the experimental
[`thread/settings/update` app-server method](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/common.rs).
The companion does not start a separate app-server or send that request to a
guessed server. Calling the live composer's callback lets Codex resolve its own
chat and server and perform its normal checks.

## Web Deck path

The Mac user chooses **Web Deck… → Start Web Deck**. `CodexUsageWeb` starts a
small `NWListener` on one available private IPv4 address and an ephemeral port;
without a private address it falls back to loopback. It is off by default and is
not restored at login. Native controls display a QR code and **Copy Pairing Link**.

The pairing URL puts a random 32-byte token in the fragment. The page removes it
from history and exchanges it through `POST /api/pair`. A link is valid for five
minutes and one use; the resulting in-memory session lasts eight hours. Static
HTML/CSS/JavaScript and the fixed state/pair/preset/logout routes are the complete
HTTP surface. It does not forward CDP requests or expose script evaluation.
Session cookies, CSRF, exact Origin/Host checks, private-peer checks, size/time
limits, and strict single-request parsing protect that limited API. Traffic is
still unencrypted HTTP: see [Security](../SECURITY.md) for the trusted-LAN boundary.

1. An authenticated `GET /api/state` supplies the configured presets, usage,
   and the visible saved chat's identity/title and current model/effort.
2. The phone sends `POST /api/preset` with its displayed slot, model, effort,
   and chat identity. The host rejects changed configuration or a busy action.
3. The fixed remote-switch operation checks that the same saved chat is still
   visible, then uses the existing selection callback and stable readback.
   The Mac need not have Codex foreground. Keyboard switching keeps its existing
   focus requirement; new unsaved drafts are not Web Deck targets.
4. The phone refreshes after the action and reports confirmed success or the
   error. A changed target requires review and a new request, not automatic retry.

**New Pairing Link** replaces an unused token while preserving paired sessions.
**Disconnect All Devices**, **Stop Web Deck**, and companion restart revoke
sessions. Stopping also closes the listener; closing the settings window alone
does not. The phone can disconnect its own session. No message sending, approval,
or question-answering operation is included.

## Setup and compatibility limits

The setup button restarts Codex, so users should finish running work first. A
successful launch does not confirm that its Chromium runtime exposed debugging.
The next preset checks the connection. A normal Dock launch may omit the options;
use setup again if needed. After initial setup, Open Codex Automatically defaults
to on. At companion startup it launches a closed Codex in the background with a
fresh loopback port. Launch at Login starts the companion, which then follows
that preference. An already running, unrecognized Codex process is never
terminated automatically; the menu requests manual reconnection instead.
Launch success still does not prove the renderer accepted debugging; applying
the next preset validates the connection. A startup-policy fixture verifies
opt-out, missing setup, launch, reuse, and manual-reconnection decisions.

The React composer shape and Chromium debugging support are internal details,
not a stable Codex extension API. Unknown structure, ambiguous windows, missing
models, or unsupported effort produce errors. The old Accessibility switcher
and its regression tests remain in source but are not the app's active path.
Control–Shift–M is no longer required for direct switching.

The local debugging port is unauthenticated and grants broad renderer access to
other local processes. It is deliberately bound to loopback, but that is not
isolation from software on the same Mac. See [Security](../SECURITY.md). Quit
Codex and launch it normally to remove the connection.

## Open-source references

- [dazer1234/codex-stream-deck](https://github.com/dazer1234/codex-stream-deck)
  (MIT): reference for Stream Deck control using CDP and native Codex Micro events.
- [mpociot/codex-micro-stream-deck-emulator](https://github.com/mpociot/codex-micro-stream-deck-emulator):
  reference for Stream Deck emulation. Its shim approach was not adopted.

These projects establish useful integration approaches; they do not prove that
this companion works with the installed Codex version. This implementation uses
the active composer's bound callback and has no Stream Deck hardware dependency.

## Verification

```bash
swift test
node --test Tests/DirectSwitching/apply-preset.test.mjs
node --test Tests/WebDeck/deck.test.cjs
swift run CodexUsage --check-direct-resources
swift run CodexUsage --check-web-resources
swift run CodexUsageWebFixture
```

The 0.6.0 verification run passed **60 Swift tests and 48 JavaScript tests**
(36 model-bridge and 12 Web Deck tests). The suites cover supported presets,
confirmation refusal, unsupported model/effort, ambiguous or changing composers,
hidden mounted pickers, stale React alternates, large trees, catalog loading,
custom model names, focus loss, retained selection, CDP result validation, and target selection.
Web Deck adds saved-target/background-selection fixtures, browser controller
tests, and HTTP/authentication tests. The real loopback-listener test pairs a
device, checks unauthenticated/CSRF rejection, dispatches an in-memory preset,
revokes the session, and stops the server. Parser cases include duplicate headers,
chunking, oversized and incomplete input, and pipelining. Other Swift tests cover
usage parsing and incremental file changes, startup policy, defaults, migration,
and the legacy Accessibility flow. Tests use controlled fixtures, not a live
Codex recording.

`CodexUsageWebFixture` serves the real bundled page and HTTP routes with a clearly
labeled `Fixture chat`, default presets, and in-memory selection. It binds only
loopback and does not depend on the automation module. It is available for
browser-to-server fixture checks without touching Codex. The recorded browser
QA used a synthetic offline fixture in Chromium: all five buttons, keyboard and
touch, stale/offline/disconnect states, and 320/390 px layouts were checked.
Both widths fit all five keys without horizontal overflow. The preview image
is visibly labeled `Fixture chat — offline UI verification`. Neither that
preview nor the loopback HTTP tests establish actual phone reachability or live
Codex switching. The agent has not tested the phone-to-Codex path.

Version 0.3.1 corrected composer discovery by mapping visible model controls to
committed React fibers. The user subsequently confirmed that switching works.
The development tool itself denied Codex control, so this is user-reported live
validation, not an automated desktop test. The five new defaults, including
Astra Ultra, are covered by fixtures; account-specific availability remains a
runtime check. No claim is made that all five new shortcuts or every failure
scenario have been manually exercised.

## Usage reader optimization

A sample of the running companion found repeated whole-file `String.split` and
`contains` work in the 30-second usage refresh. Version 0.6.0 keeps per-file
cursors and metadata, skips unchanged logs, and scans appended bytes in chunks.
It still discovers new/archived logs and resets cursors for replacement or
truncation. A partial last line is retried when more bytes arrive. Usage events
retain the same account-wide bucket selection and latest-event semantics.

Reader-only measurements on this Mac used **261 logs totaling 353.3 MiB**:

| Measurement | Before | After |
| --- | --- | --- |
| First scan wall time | 21.933 s | 3.608 s |
| Next unchanged scans | Re-read the full logs | 0.024 s / 0.020 s |
| Maximum resident memory | 236,208,128 bytes | 28,246,016 bytes |

These measure the reader's wall time and peak process memory for this dataset.
They are not an end-to-end Mac power measurement or a measured increase in
battery life. The initial scan still reads the logs; subsequent unchanged scans
check metadata without reprocessing their contents. Web Deck is optional and
the phone page pauses automatic refresh while hidden.

## Presets and migration

Slots 1–5 are Command–Control–1 through 5. Defaults are Astra Ultra, Extra High,
High, then GPT-6.1 Sol Extra High and High. Each application reloads the JSON.
The schema version remains 1. Valid old three-slot files are backed up next to
the original before an atomic rewrite. Exact previous defaults become the new
five defaults; customized slots 1–3 are retained and defaults 4–5 are appended.
Five-slot files are not rewritten. Invalid data keeps the last valid configuration.
