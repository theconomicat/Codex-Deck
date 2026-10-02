# Direct model switching in 0.5.0

Status: **internal integration; working 0.3.1 switching confirmed by the user**
on Codex 26.928.31416 (2026-10-02). Version 0.5.0 uses the same selection path,
with five presets, legacy JSON migration, and optional startup connection. The implementation is independently
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
swift run CodexUsage --check-direct-resources
```

The direct-switching suite includes 27 JavaScript tests and four Swift tests
(one with six failure parameter cases). Coverage includes supported presets,
confirmation refusal, unsupported model/effort, ambiguous or changing composers,
hidden mounted pickers, stale React alternates, large trees, catalog loading,
custom model names, focus loss, retained selection, CDP result validation, and target selection.
Thirty-four other Swift tests cover usage parsing, startup policy, five-slot defaults, migration, and the legacy
Accessibility flow. Tests use controlled fixtures, not a live Codex recording.

Version 0.3.1 corrected composer discovery by mapping visible model controls to
committed React fibers. The user subsequently confirmed that switching works.
The development tool itself denied Codex control, so this is user-reported live
validation, not an automated desktop test. The five new defaults, including
Astra Ultra, are covered by fixtures; account-specific availability remains a
runtime check. No claim is made that all five new shortcuts or every failure
scenario have been manually exercised.

## Presets and migration

Slots 1–5 are Command–Control–1 through 5. Defaults are Astra Ultra, Extra High,
High, then GPT-6.1 Sol Extra High and High. Each application reloads the JSON.
The schema version remains 1. Valid old three-slot files are backed up next to
the original before an atomic rewrite. Exact previous defaults become the new
five defaults; customized slots 1–3 are retained and defaults 4–5 are appended.
Five-slot files are not rewritten. Invalid data keeps the last valid configuration.
