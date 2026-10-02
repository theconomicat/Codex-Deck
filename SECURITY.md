# Security

Codex-Usage reads local usage events from `~/.codex/sessions/**/*.jsonl` and
`~/.codex/archived_sessions/**/*.jsonl`. It does not read `auth.json`, browser
cookie stores, Keychain items, or API keys. It sends no telemetry or requests to
an Internet service. Usage checks read local files; direct switching uses
loopback. The optional Web Deck accepts authenticated requests on a private LAN.

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
before reporting success. Keyboard shortcuts stop when the active chat or focus
changes. Web Deck allows another Mac app to be foreground, but requires the exact
saved-chat identity shown on the phone to remain selected. Both paths reject an
unavailable model or unrecognized internal structure. The script does
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

## Web Deck

Web Deck is **off by default**. The Mac user explicitly starts it from the menu;
launch-at-login does not enable it. It binds a selected private IPv4 interface,
or loopback when no private interface is available. It does not open a router
port, use a relay, or expose/proxy the Chromium debugging endpoint. Its fixed API
can read deck status, pair/logout, and apply one of the five configured presets.
There is no arbitrary command, JavaScript, file, message, approval, or question
response endpoint.

This is **plain HTTP for trusted private networks**. It is not an Internet-facing
service. Pairing controls access but does not encrypt traffic or protect against
someone intercepting or modifying traffic on that network. Do not use it on
untrusted public/guest Wi-Fi, forward its port, or expose it through a tunnel.
The page shares the selected chat's ID/title, current model/effort, configured
presets, and quota summary with paired devices; it does not share transcript or
prompt contents.

- A random 32-byte pairing token is valid for five minutes and a single use.
  It is carried in the link fragment, removed from browser history by the page,
  and exchanged through the same-origin pairing endpoint. Keep the link/QR private.
- Each device receives an eight-hour `HttpOnly`, `SameSite=Strict` session cookie
  and a separate CSRF token. Mutations require that token and an exact matching
  Origin. Cookies cannot use `Secure` because this local service uses HTTP.
- Sessions remain only in the companion's memory. Stop/restart revokes them;
  **Disconnect All Devices** also revokes them. **New Pairing Link** replaces the
  unused pairing token but leaves already paired devices connected. A phone's
  **Disconnect** action removes only its session.
- Requests must use the selected host/port and a private IPv4 peer. Cross-origin
  requests are rejected, no CORS permission is provided, and response headers
  disallow embedding the page. Fixed asset routes do not resolve filesystem paths.
- The server caps requests at 32 KiB, headers at 8 KiB, connections at 16, paired
  sessions at eight, and connection lifetime at ten seconds. It rejects duplicate
  headers, chunked encoding, unsupported framing, and multiple requests per
  connection. Failed pairing attempts are rate-limited.

The phone submits its displayed chat ID and preset values. The companion checks
them against the current saved chat and configuration before applying the native
model callback, then verifies the resulting model/effort. A stale target is an
error, not permission to switch another chat. Codex's confirmation handling stays
in place. If a timeout occurs after applying a change, inspect the current model
before retrying.

Automated verification uses isolated HTTP, composer, and browser fixtures. Actual
phone-to-Codex operation has not been agent-tested. Private-LAN reachability also
depends on macOS local-network/firewall permission, the Mac staying awake, and
the access point allowing devices to communicate.

Report security issues privately when GitHub private vulnerability reporting is
enabled. Otherwise open an issue without secrets or sensitive local paths.
