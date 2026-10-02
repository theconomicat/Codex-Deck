# Contributing

Keep this a small macOS Codex companion: quota visibility, model preset shortcuts,
and the same five presets on a paired phone's Web Deck.
Use native AppKit controls and avoid extra dependencies for small platform features.
The JavaScript test suite uses only Node.js built-ins.

```bash
swift test
node --test Tests/DirectSwitching/apply-preset.test.mjs
node --test Tests/WebDeck/deck.test.cjs
swift run CodexUsage --validate-presets presets.example.json
swift run CodexUsage --check-web-resources
./Scripts/package_app.sh
```

- Explain the problem and resulting behavior.
- Add focused regression tests for parser, preset, transport, and composer changes.
- Never read or print Codex auth tokens or transcript content.
- Missing quota windows stay absent; expired data must not become fabricated 100% quota.
- Keep usage refreshes incremental: unchanged logs must not be reread, and appends, partial writes, replacement, truncation, and archived files must preserve correct quota selection. Report performance measurements separately from battery-life claims.
- Preserve unfinished prompts. Do not type prompt text or send Return.
- Preserve Codex's own model confirmation and permission checks.
- Keep the debugging connection on loopback; automatic startup requires completed initial setup and an enabled auto-launch preference. Never terminate an existing Codex during automatic startup.
- Report success only after both model and effort are verified. Reject ambiguous targets.
- Web Deck stays opt-in for each companion run. Keep its API limited to state, pairing/logout, and configured presets; never proxy CDP or accept arbitrary commands/code. Require authenticated sessions, CSRF, exact Origin/Host checks, and private-interface binding.
- A remote preset must match the displayed saved chat and the current slot/model/effort. Codex may be in the background; keyboard shortcuts retain their foreground restriction. Preserve native confirmations and reject stale targets.
- Keep both READMEs, the example/schema, and security notes in sync.

Before claiming live compatibility, manually verify all five shortcuts against the
stated Codex version with direct switching enabled. Include an unfinished prompt,
an unavailable model/effort, a required confirmation, a focus or chat change,
multiple windows, invalid JSON, a closed connection, and shortcut conflicts.
Record what was actually checked. Compilation, a passing CDP fixture, and a setup
success message do not establish that the live Codex composer changed.

For browser QA, run `swift run CodexUsageWebFixture` and open its printed pairing
URL. This is the real HTTP server bound only to `127.0.0.1`, with in-memory
`Fixture chat` state and no Codex automation dependency. Check desktop/mobile
layout, pairing, all five selections, disconnect, inaccessible/expired sessions,
and paused polling while hidden. Restart it for a fresh one-use link. Do not
present fixture screenshots as proof of live phone/Codex operation.

Build the host alone with `swift build --product CodexUsageWebFixture`. The
committed mobile preview uses a synthetic offline browser fixture and is labeled
accordingly; keep that provenance clear if replacing it.

For an authorized manual phone check, record the Mac/Codex/browser versions,
same-Wi-Fi reachability, pairing/replay/expiration, preset changes, stale-chat
rejection, background Codex, revocation, and app restart. Keep QR tokens and
private chat names out of published screenshots.

Record whether live verification was performed by a tester or reported by a user.
If a development tool blocks Codex access, do not bypass that boundary through
another transport. User confirmation of 0.3.1 is recorded in the compatibility notes;
it does not mean later changes or every failure scenario were manually tested.
