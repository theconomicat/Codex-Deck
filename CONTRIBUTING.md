# Contributing

Keep this a small macOS Codex companion: quota visibility and model preset shortcuts.
Use native AppKit controls and avoid extra dependencies for small platform features.
The JavaScript test suite uses only Node.js built-ins.

```bash
swift test
node --test Tests/DirectSwitching/apply-preset.test.mjs
swift run CodexUsage --validate-presets presets.example.json
./Scripts/package_app.sh
```

- Explain the problem and resulting behavior.
- Add focused regression tests for parser, preset, transport, and composer changes.
- Never read or print Codex auth tokens or transcript content.
- Missing quota windows stay absent; expired data must not become fabricated 100% quota.
- Preserve unfinished prompts. Do not type prompt text or send Return.
- Preserve Codex's own model confirmation and permission checks.
- Keep the debugging connection on loopback; never enable it without the user's setup action.
- Report success only after both model and effort are verified. Reject ambiguous targets.
- Keep both READMEs, the example/schema, and security notes in sync.

Before claiming live compatibility, manually verify all five shortcuts against the
stated Codex version with direct switching enabled. Include an unfinished prompt,
an unavailable model/effort, a required confirmation, a focus or chat change,
multiple windows, invalid JSON, a closed connection, and shortcut conflicts.
Record what was actually checked. Compilation, a passing CDP fixture, and a setup
success message do not establish that the live Codex composer changed.

Record whether live verification was performed by a tester or reported by a user.
If a development tool blocks Codex access, do not bypass that boundary through
another transport. User confirmation of 0.3.1 is recorded in the compatibility notes;
it does not mean later changes or every failure scenario were manually tested.
