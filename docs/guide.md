# Codex Deck guide

[← README](../README.md) · [한국어](guide.ko.md)

## Installation

Use the build commands in the README for the current deck. Published release downloads currently predate its model and phone controls. Build requirements are macOS 13+, Swift 6, Git, and the installed, signed-in Codex desktop app. Node.js is only needed for development tests.

Move the generated `Codex Deck.app` into `/Applications`. Quit any old copy first. This is a menu bar app; it does not keep a Dock window open. Local builds are ad-hoc signed, not Apple-notarized. If macOS blocks launch, verify the source and use the app-specific opening option in System Settings → Privacy & Security.

**Enable Direct Switching…** opens setup. Finish running work, then use its “Restart Codex · connect direct switching” button. Open one main Codex window with a visible chat composer. A successful preset change briefly shows its name in the menu bar and `Applied:` in the menu. Setup completing alone does not verify a model change.

Shortcuts work only when Codex is in front. Models and reasoning levels must be available to your account. If Codex asks for confirmation, finish it there; an unsupported model or effort is not silently substituted.

## Phone connection

1. Complete direct switching setup. Keep a **saved chat** and its composer visible in one main Codex window.
2. Keep the Mac awake and both devices on the same trusted private Wi-Fi.
3. Choose **Web Deck… → Start Web Deck**, then scan the QR or open the full **Copy Pairing Link** URL. The bare IP address does not pair a device.
4. Tap the usage ring to check the target chat before applying a preset.

The server is off by default and does not start at login. Closing its settings window leaves it running. Stopping the server or restarting the companion revokes sessions; start it and pair again.

Pairing links last **five minutes and one use**. Choose **New Pairing Link** for another device. Paired sessions last up to eight hours. **Disconnect All Devices** revokes them all. Keep pairing links private.

Use **Usage → Enter full screen** where supported. On iPhone, Safari's **Share → Add to Home Screen** offers a standalone view; it may need its own pairing. Landscape and portrait both work. Mac keyboard shortcuts require Codex in front; phone controls can work while another Mac app is foreground.

The connection is **local HTTP**, without transport encryption. Use a trusted network and do not forward the port to the Internet. Guest Wi-Fi isolation can block access; allow the app's local-network/firewall request if needed. Restart Web Deck after changing Wi-Fi or IP address. A `127.0.0.1` URL works only on the Mac. See [Security](../SECURITY.md).

## Button settings

Open **Edit Button Settings…** in the Mac menu. The file stays at:

```text
~/Library/Application Support/Codex-Usage/presets.json
```

The folder retains the previous app name so existing settings survive updates. If JSON has no editor associated with it:

```bash
open -a TextEdit "$HOME/Library/Application Support/Codex-Usage/presets.json"
```

Save plain text without comments or trailing commas. Start with the [complete example](../presets.example.json); the [schema](presets.schema.json) provides editor validation.

| Field | Meaning |
| --- | --- |
| `version` | Keep `1`; this is the settings format. |
| `slot` | Include `1`–`5` exactly once. Sets deck position and `⌘⌃number`. Array order does not matter. Exchange two slot numbers to swap keys. |
| `model` | A Codex display name or ID, such as `GPT-6 Astra` or `gpt-6-astra`. `GPT-6 Sol` and `GPT-6.1 Sol` are different models. |
| `effort` | A supported value: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, `ultra`. Extra High is `xhigh`. |
| `label` | Optional web name, 1–32 characters with no surrounding whitespace or control characters. Omit for automatic model names. |

Save to apply on the next shortcut or visible-page refresh (about five seconds). **Reload Button Settings** updates the Mac menu immediately. Invalid JSON keeps the last valid settings active; a fresh launch uses defaults if the file is invalid. Existing three-slot settings migrate with a backup beside the file.

Labels only change the web key face; actual model names remain in its tooltip, accessible name, and Mac menu. These are five model presets with fixed Command–Control modifiers, not arbitrary macros.

To validate the file without changing Codex:

```bash
"/Applications/Codex Deck.app/Contents/MacOS/CodexUsage" \
  --validate-presets "$HOME/Library/Application Support/Codex-Usage/presets.json"
```

## Everyday controls

**Models / Presets** toggles between the model catalog and your saved keys. The horizontal slider changes the current model's reasoning effort on release. Neither action rewrites JSON: pressing a preset restores its saved combination.

**Mac mic** starts/stops Codex dictation on the Mac, inserting text without sending it. Finish microphone permission prompts on the Mac. Stop recording before closing the deck; losing the connection does not guarantee recording stops.

**Requests** appears for supported questions and approvals in the current chat. Review their full details before responding. Unsupported requests must be completed in Codex. [Full control reference →](codex-micro.md)

## Usage and frame colors

<img src="menu-bar-preview.png" alt="Menu bar quota: 94 percent remaining" width="185" />

The percentage means **remaining quota**. Usage is read from local Codex session events every 30 seconds; **Refresh Usage** checks immediately. “Data as of” is the event time. A refresh does not request new quota from the service. Expired or missing data stays unknown until Codex records a fresh event.

The frame follows the selected chat: white idle, green unread completion, blue working, peach input needed, red chat error. Unknown or disconnected is gray. The visible web page checks about every five seconds. [State source and limits →](codex-micro.md#status-frame)

## Startup, updates, and removal

Enable **Launch at Login** and **Open Codex Automatically** after initial setup to open the connected Codex app when the companion starts. If Codex is already running without that connection, finish work and reconnect through setup. The companion does not repeatedly reopen a closed Codex app. Web Deck still starts manually.

To update, quit the companion, replace it in `/Applications`, and launch the new copy. If upgrading from Codex-Usage, quit and remove that old app copy too. JSON settings remain outside the app. Check login settings after renaming; pair the phone again after restart.

To uninstall, disable Launch at Login, quit, and move the app to the Trash. Quit/relaunch Codex normally to close its debugging connection. Delete `~/Library/Application Support/Codex-Usage` only if you also want to remove saved presets.

## Troubleshooting

| Problem | Try this |
| --- | --- |
| Shortcut does nothing | Put Codex in front; confirm the companion is running and your JSON is valid. |
| Connection or ambiguous-composer error | Keep one main Codex window and saved chat composer visible; finish work and reconnect through setup. |
| Model/effort rejected | Check your account's available models, supported efforts, and any confirmation in Codex. |
| Change timed out | Check the current Mac selection before retrying; it may have changed before confirmation failed. |
| Phone cannot connect | Check same Wi-Fi, awake Mac, running server, firewall, and client isolation. Pair with a fresh complete link. |
| Chat/preset/request changed | Refresh, verify the target chat, then retry. |
| No click sound | Check media volume, mute, and browser audio settings. The app cannot override them. |
| Mic unknown or request missing | Inspect and finish the action directly in Codex. |
| Stale usage | Run a Codex task to produce a new usage event, then refresh. |

If number shortcuts select chats, optionally merge the [keybinding example](codex-keybindings.example.json) into `~/.codex/keybindings.json`, preserving unrelated entries. It also disables the listed Command/Control-number navigation shortcuts. Remove those added `null` entries to undo it. The app does not install these overrides automatically; use your configured `CODEX_HOME` if different.

The integration depends on Codex internals. Offline tests cover the renderer and adapter contracts, but do not establish every live desktop version or physical-phone behavior. For implementation and test details see [direct switching](model-switching.md), [control limits](codex-micro.md#verification-and-current-limits), and [contributing](../CONTRIBUTING.md).
