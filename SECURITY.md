# Security

Codex-Usage reads local usage events from `~/.codex/sessions/**/*.jsonl` and
`~/.codex/archived_sessions/**/*.jsonl`. It does not read `auth.json`, browser
cookies, Keychain items, or API keys. It sends no telemetry or external network requests.

## Direct switching

The user enables this experimental mode by clicking the restart button in
**Enable Direct Switching…**. This terminates and relaunches Codex with Chromium
remote debugging bound to `127.0.0.1` on a randomly selected port. Finish running
work before restarting. Setup alone does not verify that the connection works.

After initial setup, **Open Codex Automatically** defaults to on. When the
companion starts (including login if Launch at Login is enabled), it can open a
closed Codex app with the same local debugging options. It never automatically
terminates an already running Codex. Turn this option off to stop future automatic
launches. It does not continuously reopen Codex after you quit it.

Remote debugging is a powerful, unauthenticated local interface. Other processes
on this Mac may use it to inspect or execute code in the Codex renderer, including
access to chat content. Loopback binding prevents direct access from another
machine; it does not isolate the endpoint from local software. Only enable this
mode if you accept that access. Quit Codex and reopen it normally to close the
endpoint. A random port is not authentication.

The companion validates the WebSocket's loopback host, configured port, scheme,
and absence of credentials. It requires one matching main-window target, finds
one active composer, and calls the composer's existing model-and-effort callback
with Codex's native confirmation and permission checks. It verifies both values
before reporting success. It stops when the active chat or focus changes, the
model is unavailable, or the internal structure is unrecognized. The script does
not read transcript text or type into the prompt. A timeout or partial failure
may follow an applied change; inspect the selection before sending a prompt.

This mode does not use Accessibility permission, modify the installed Codex
bundle, edit chat databases, or replace the app-server's permission decisions.
It relies on internal runtime structure and can break after Codex updates. A user confirmed direct switching in version 0.3.1 on Codex 26.928.31416;
this does not establish compatibility with every version or account. Automated
fixtures do not replace live validation of new integrations.

Preset JSON is data only: model names, effort values, and slots 1–5. Values are
JSON-encoded when passed to the script. Presets cannot specify shell commands,
executable paths, arbitrary JavaScript, or a remote debugging host.

Report security issues privately when GitHub private vulnerability reporting is
enabled. Otherwise open an issue without secrets or sensitive local paths.
