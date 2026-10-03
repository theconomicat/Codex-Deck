# Codex Deck

**English · [한국어 README 바로 보기 →](README.ko.md)**

**Save your model and reasoning presets. Switch with a shortcut or a tap. See your Codex usage at a glance.**

Codex Deck is an open-source macOS companion for Codex. Set up the model and reasoning level you use together—such as Astra Ultra or Sol High—then apply the combination to your current chat in one action. Use keyboard shortcuts on your Mac or turn your existing phone or tablet into a deck on the same Wi-Fi. Previously named Codex-Usage.

## Why I built it

I wanted to see my remaining Codex usage without digging through menus. Switching models and reasoning levels also meant moving the mouse, opening the picker, and clicking through options over and over. Those small interruptions added up during everyday work.

I built Codex Deck to keep my favorite combinations ready and switch them instantly from a shortcut or my phone. I also wanted a software alternative to the controls I would use on OpenAI's Codex Micro, using a phone I already own without buying dedicated hardware. This is an independent open-source companion, not an official OpenAI product or a complete replacement for every Micro feature.

## What it does

- **Model + reasoning presets:** save five frequently used combinations in editable JSON. Each preset applies both values together.
- **Mac keyboard shortcuts:** press `⌘⌃1`–`⌘⌃5` while Codex is in front to switch the current chat without opening its model picker.
- **Phone or tablet deck:** tap the same presets from a paired browser on your Wi-Fi. Use portrait or landscape, a model catalog, and a horizontal reasoning slider. No Codex Micro or Stream Deck hardware is needed.
- **Usage at a glance:** see remaining quota in the macOS menu bar and as a percentage ring on the deck.

The deck also supports Mac dictation and responses to the active chat's supported pending questions or approval requests. [See the control guide](docs/codex-micro.md).

## Preview

### App menu

<img src="docs/app-menu.png" alt="Codex Deck menu grouping five shortcuts with separate preset settings and automatic launch options" width="560" />

User-provided screenshot of the running 0.5.0 app, under its previous Codex-Usage name. All five shortcuts form one group. In the current app, **Edit Button Settings…** opens the JSON directly from the main menu; the older submenu shown here has been removed. A single weekly quota is labeled `Usage` instead of `1w`.

### Menu bar usage

<img src="docs/menu-bar-preview.png" alt="Codex Deck menu bar showing 94 percent remaining in a single green quota ring" width="185" />

User-provided screenshot of a weekly-only account: the green ring shows 94% remaining. The adjacent Codex icon belongs to Codex itself. Values update from local Codex usage events.

### Phone Web Deck

<img src="docs/web-deck-landscape.png" alt="Landscape Web Deck: five raised model keys and a circular remaining-usage tile" width="844" />

<img src="docs/web-deck-mobile.png" alt="The same six-key deck arranged in two columns for portrait use" width="260" />

<img src="docs/web-deck-models.png" alt="Codex Deck showing model names and a Presets button to return" width="840" />

<img src="docs/web-deck-slider.png" alt="Main deck after changing Astra Ultra to Astra High with the always-visible effort slider" width="844" />

<img src="docs/web-deck-questions.png" alt="A pending question with selectable answers and a request-specific text field" width="500" />

Version 0.9.5, rendered with synthetic offline fixture data. These landscape, portrait, model catalog, slider, and question previews illustrate the interface; they are not photos of a phone controlling live Codex. The recording state, requests, and quota in these examples are simulated.

---

## Default shortcuts

Hold **Command + Control**, press a number, then release it.

| Shortcut | Model | Reasoning effort | JSON value |
| --- | --- | --- | --- |
| `⌘⌃1` | GPT-6 Astra | Ultra | `ultra` |
| `⌘⌃2` | GPT-6 Astra | Extra High | `xhigh` |
| `⌘⌃3` | GPT-6 Astra | High | `high` |
| `⌘⌃4` | GPT-6.1 Sol | Extra High | `xhigh` |
| `⌘⌃5` | GPT-6.1 Sol | High | `high` |

Shortcuts are registered **only while Codex is the foreground app**. Other applications keep their own shortcuts.
Your Codex account must offer the selected model and effort. Unsupported choices, including Ultra where unavailable, produce an error rather than silently falling back.

## 1. Install

### Install the app

1. Download `Codex-Deck-macos.zip` from the desired [release](https://github.com/theconomicat/Codex-Usage/releases).
   **Model/effort controls, Mac mic, and pending-request controls require 0.8.0 or newer**. Web Deck first shipped in 0.6.0; the five keyboard presets require 0.4.0 or newer. If that version is not published yet, build from source below.
2. Unzip and move `Codex Deck.app` into **`/Applications`**.
3. Quit an older running copy with **Quit Codex Deck** before opening the new app.
4. Click the Codex Deck icon in the macOS menu bar. It is a menu bar app; a persistent Dock window is not expected.

Requires macOS 13+ and an installed, signed-in Codex desktop app. You can use the quota meter without enabling direct model switching.
Local builds are ad-hoc signed and not Apple-notarized. If macOS blocks launch, verify the source, then check the app-specific opening option in System Settings → Privacy & Security.

### Build from source

Install Git and Xcode/Command Line Tools supporting Swift 6. Node.js 22+ is needed for JavaScript tests only, not to run the packaged app.
There are no external Swift packages or npm dependencies.

```bash
git clone https://github.com/theconomicat/Codex-Usage.git
cd Codex-Usage
./Scripts/package_app.sh
```

Move the generated `Codex Deck.app` to `/Applications` and launch it. Quit the old copy before replacing an existing installation.

## 2. Connect direct switching once

1. Finish running Codex work. **This setup restarts Codex.**
2. Choose **Enable Direct Switching…** in the companion menu. The setup window opens automatically on first launch.
3. Click **Codex 재시작 · 직접 전환 연결** (“Restart Codex · connect direct switching”).
4. In the relaunched Codex app, open one main window and focus the chat you want to change. Its composer and model/effort control must be visible.
5. Press and release `⌘⌃4`, for example, to select **GPT-6.1 Sol · Extra High**.

After success, the preset name briefly appears in the menu bar and the menu status reads `Applied:`.
The setup window confirms the launch, not a successful model change. The first shortcut checks the connection and verifies both selection values.

**Accessibility permission is not required.** The current direct backend does not use the permission requested by older builds.
You do not need Control–Shift–M or an open model picker.

Direct mode opens a debugging connection on `127.0.0.1` on this Mac, then invokes Codex's existing selection callback.
The connection is unauthenticated and gives other local processes powerful renderer access. Read [Security](SECURITY.md) before enabling it.
Fully quit Codex and launch it normally to close that connection.

## 3. Everyday use

- Focus the desired Codex chat and press/release `⌘⌃1` through `⌘⌃5`. Successful switching does not open a model popup.
- Both the model and reasoning effort change for subsequent turns. The companion does not restart an answer already generating or send a message.
- Your unfinished prompt is preserved. If Codex requires confirmation, complete its confirmation and retry.
- Enable **Launch at Login** and **Open Codex Automatically** to start the companion at login and open a closed Codex app with direct switching. Complete initial setup once; Codex auto-launch defaults to on for users who have already connected.
- If a normal Dock launch or Codex update breaks the connection, use **Enable Direct Switching…** again.

### Automatic connection at login

1. Complete direct-switching setup once.
2. Check both **Launch at Login** and **Open Codex Automatically** in the menu.
3. At the next login, the companion opens Codex with its local connection options. You do not need to press the connection button again.

An already connected Codex process is reused. If Codex has already launched normally, the companion preserves running work and shows a reconnection message instead of terminating it.
Finish the work and use **Enable Direct Switching…** in that case. Auto-launch runs once when the companion starts; it does not repeatedly reopen Codex after you quit it.
Turn off **Open Codex Automatically** to start only the usage companion. Turning it on does not forcibly restart an existing Codex session.

### Use your phone as a Web Deck

1. Complete **Enable Direct Switching…** on the Mac first. Keep one main Codex window open on a **saved chat**, with its composer visible. The Web Deck can switch models while another Mac app is in front; keyboard shortcuts still require Codex in front.
2. Connect the Mac and phone to the **same trusted private Wi-Fi**. Keep the Mac awake and Codex Deck running.
3. Choose **Web Deck… → Start Web Deck** in the Mac menu. This starts a small local HTTP server; it is off by default and does not start automatically at login.
4. Scan the QR code with your phone, or choose **Copy Pairing Link** and open that complete link in the phone's browser. The bare IP address opens the page but does not pair a device.
5. Tap the **percentage ring (Usage)** to review the active chat, close the details, then tap a model key. The page uses the first five configured presets in slot order from the same `presets.json` as the keyboard shortcuts. A key turns green after the host confirms the selection.
6. The preset view uses **3 × 2 landscape** or **2 × 3 portrait**. The model catalog uses four columns in landscape and two in portrait. Five square model keys and a usage tile form a centered white-and-gray physical keypad, sized to fit the screen with the control strip. The effort slider stays directly below the keys. **Models / Presets**, **Mac mic**, and waiting **Requests** sit beside the keys in landscape or below the slider in portrait, without a page header.
7. Tap **Usage → Enter full screen** in supported browsers. On iPhone, use Safari's **Share → Add to Home Screen** and open the saved deck; pair again if that standalone browser has a separate session.

White keys have a recessed face, gray raised edge, short press effect, and an always-enabled click from a bundled audio file; there is no sound toggle. A supported-device vibration accompanies the press. Playback starts from your tap and does not run continuously. The page cannot override device volume, hardware mute, or browser audio restrictions. If you hear nothing, check the media volume and browser sound settings. Reduced-motion preferences disable key movement; unsupported sound, vibration, or fullscreen does not block the controls.

Preset keys show the **model family prominently** and the **reasoning level beneath it**: `Astra / Ultra`, `Astra / Extra High`, `Astra / High`, `Sol / Extra High`, and `Sol / High`. There are no printed slot numbers or inactive indicator dots; only the selected key shows its small indicator. Full model names remain in **Models**, the slider, tooltips, and accessible labels. If your presets contain different versions of the same family, the keys include the version (`Sol 6`, `Sol 6.1`). Custom model names are preserved. These shorter labels do not change saved IDs, efforts, or keyboard mappings. Set an optional `label` in JSON to use your own button name, such as `Focus`; the reasoning level remains visible below it.

The 0.9.1 tone has a soft attack and a rounded 180 ms tail. Rapid button presses can overlap briefly instead of cutting off the previous tone; the slider plays once on release rather than at every crossed step. The original sound can be regenerated with `python3 Scripts/generate_feedback_sound.py`.

The sixth tile centers **remaining quota as a percentage only** inside a larger ring. It has no `Usage` caption, ellipsis, or “remaining” text. Tap anywhere on the tile for **Usage** details and reset information; button settings live in the Mac menu. It prioritizes the weekly window (otherwise the first available window). Missing or expired quota, or a lost connection, displays **—**. Connection and error notices appear only when needed.

A pairing link expires after **5 minutes** and can be used **once**. Choose **New Pairing Link** for another device or an expired link; existing paired devices stay connected. Each paired browser session lasts up to **8 hours**. Keep pairing links private.

The wider outer frame follows the current chat’s status, using the [official Micro color meanings](https://learn.chatgpt.com/docs/features/codex-micro):

| Frame | Chat state |
| --- | --- |
| White | Idle |
| Light green | Complete with an unread update |
| Light blue | Thinking / working |
| Peach / amber | Requires input or approval |
| Red | Chat error |

Only the frame changes color; the white keys and gray inner board stay legible. **Usage** also names the state. Disconnected or unrecognized status is gray. Colors update with the existing five-second poll while the page is visible; a preset change does not trigger the completion color. Green clears when Codex marks the update read. See [frame previews and limits](docs/codex-micro.md#status-frame).

**Disconnect All Devices** revokes every session and creates a fresh link. **Stop Web Deck** closes the server and revokes all sessions. Closing only its settings window keeps it running. After a companion restart, start Web Deck and pair again; neither the server state nor sessions are saved. A phone can also use **Usage → Disconnect** to end its own session.

If the active chat, preset, model catalog, or waiting request changes before an action is applied, the action is rejected. Open **Usage**, refresh, check the active chat, and try again. New unsaved drafts and ambiguous composers are not remote targets.

#### Choose a model and slide the effort control

Selections appear immediately as pending. A confirmed response keeps the same key and slider position, without briefly repainting the old selection. Dragging is continuous and release selects the nearest supported level. You can keep adjusting while a change is in progress: only the most recent trailing value is sent after the current request. A failure drops queued input and restores the last confirmed state; changing chats during a drag cancels that gesture.

Use the **slider directly on the deck** to change the current model's effort. Tap **Astra / Ultra**, then slide to **High** and release: the chat becomes **Astra High**, without opening a dialog or changing the model. The bar follows every confirmed preset selection and exposes only that model's supported levels. Arrow keys move one level, and Home/End move to the minimum/maximum. The Mac confirms the result before the deck shows success.

Tap **Models** to replace the preset keys with the active Codex composer’s model catalog. These keys show model names only. Tap a model to apply it; the current effort is preserved when supported, otherwise High is used (or the model’s first supported level). The slider follows the confirmed model.

The same button now reads **Presets**. Tap it, or press Escape, to return to your five saved combinations and usage ring. Returning changes only the view; it does not restore an earlier model or edit `presets.json`. There are no sets or pages to configure. The effort slider and Mac mic remain available in both views. Longer model catalogs scroll inside the deck.

This changes the current chat, not `presets.json`. To make a choice one of the five permanent keys, use **Edit Button Settings…** on the Mac as described below.

#### Use the Mac microphone

Tap **Mac mic** to begin Codex dictation using the **microphone connected to the Mac**, then tap **Stop mic**. Stopping inserts the transcript into the Mac composer; it does **not** send a chat message. Review and send from Codex when ready. A recording already started in Codex is shown as **Mic on Mac** and must be stopped there.

Codex dictation must be available in that composer, and macOS must allow **Codex** to use the microphone. Complete any native permission prompt on the Mac; the phone cannot grant it. The web page does not capture or upload your phone's microphone audio. Realtime voice calls are not controlled by this button.

**Stop recording before closing the page or disconnecting.** Browser closure, network loss, or stopping Web Deck may leave Mac dictation recording. **Mic unknown** means the deck cannot confirm its state; check and stop it in Codex on the Mac.

#### Respond to a waiting Codex request

The **Requests** button appears when a supported request is waiting in the active saved chat. Open it, check the chat title and full request details, then respond:

- **Allow once / Deny:** review a command, file changes, or the exact requested permission scope. Approval is limited to that request; permission requests use Codex's current-turn scope. There is no always-allow or blanket permission control.
- **Questions:** choose one of Codex's options. Use **Other** or a freeform field only when that question allows it, answer every question, then submit. This is a response to that pending question, not a general chat input.

Already answered or changed requests are rejected rather than applied to a different request. Plan implementation prompts, generic option pickers, requests too large to show completely, and unrecognized structures must be handled in Codex on the Mac. The deck does not expose unrelated chats, arbitrary message sending, or shell/code execution controls. See the [Micro-style controls guide](docs/codex-micro.md) for scope and research notes.

The phone connection is **HTTP on the local network**, not an Internet service. Pairing does not encrypt traffic: use a network you trust, do not forward the port, and read [Security](SECURITY.md). If macOS asks, allow Codex Deck's local-network access or incoming connection. Guest Wi-Fi/client isolation can prevent devices from reaching each other. Web Deck needs a private IPv4 address (`10.x.x.x`, `172.16–31.x.x`, or `192.168.x.x`); a displayed `127.0.0.1` address works only on the Mac. After changing networks, stop and start Web Deck to obtain a new address and pairing link.

### Menu reference

| Item | Action |
| --- | --- |
| Refresh Usage | Scan local usage records immediately. |
| Five model presets | Apply that preset to the current chat; Codex must be foreground. |
| Enable Direct Switching… | Set up the connection by restarting Codex. |
| Edit Button Settings… | Open JSON directly to edit button names, models, reasoning levels, and numbered mappings. |
| Reload Button Settings | Read saved JSON and refresh the menu. |
| Web Deck… | Start or stop phone access, show a pairing QR/link, and disconnect devices. |
| Launch at Login | Toggle companion startup at login. |
| Open Codex Automatically | Open a closed Codex app with direct switching when the companion starts; requires initial setup. |
| Quit Codex Deck | Quit the companion. To close debugging too, quit Codex and relaunch it normally. |

## 4. Customize buttons and shortcuts

1. Choose **Edit Button Settings…**.
2. Change `model` and `effort` in a text editor. Use `slot` for both the deck position and shortcut number; optionally add `label` for the name on the web key.
3. Save. The next shortcut automatically reloads the file, and the visible Web Deck picks it up on its next five-second refresh. Choose **Reload Button Settings** to update the Mac menu immediately.

The file is created at:

```text
~/Library/Application Support/Codex-Usage/presets.json
```

If JSON has no editor associated with it, open it in TextEdit:

```bash
open -a TextEdit "$HOME/Library/Application Support/Codex-Usage/presets.json"
```

Save as plain text and keep the filename `presets.json`. The complete default configuration is:

```json
{
  "version": 1,
  "presets": [
    { "slot": 1, "model": "GPT-6 Astra", "effort": "ultra" },
    { "slot": 2, "model": "GPT-6 Astra", "effort": "xhigh" },
    { "slot": 3, "model": "GPT-6 Astra", "effort": "high" },
    { "slot": 4, "model": "GPT-6.1 Sol", "effort": "xhigh" },
    { "slot": 5, "model": "GPT-6.1 Sol", "effort": "high" }
  ]
}
```

| Field | Rule |
| --- | --- |
| `version` | Keep `1`. This is the configuration format, not the app version. |
| `slot` | Include numbers `1` through `5` exactly once. `slot: 4` means the fourth deck key and `⌘⌃4`. Array order does not matter. To exchange keys, exchange their slot numbers. |
| `model` | A display name or ID from your Codex catalog, such as `GPT-6 Astra`, `gpt-6-astra`, `GPT-6.1 Sol`, or `gpt-6.1-sol`. |
| `effort` | A supported value: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, or `ultra`. |
| `label` | Optional web key name, 1–32 characters with no surrounding whitespace or control characters. Omit it for the automatic model-family label. |

**Extra High is `xhigh`**; Ultra is `ultra`. Do not enter `extra high` in JSON.
Model matching ignores the `GPT-` prefix, case, spacing, and punctuation, but must identify exactly one catalog entry.
`GPT-6 Sol` and `GPT-6.1 Sol` are different models.

For example, replace only slot 5's entry to use GPT-6 Luna / High:

```json
{ "slot": 5, "model": "GPT-6 Luna", "effort": "high" }
```

To call the first web key **Focus** while keeping Astra Ultra and `⌘⌃1`, replace its entry with:

```json
{ "slot": 1, "model": "GPT-6 Astra", "effort": "ultra", "label": "Focus" }
```

The key reads **Focus / Ultra**. Its tooltip, accessible name, and the Mac menu still identify the actual model. A label only changes display text; it never changes the model sent to Codex. Short names fit best.

To restore defaults, replace your file with the complete JSON above or [presets.example.json](presets.example.json), then save.
Use the [JSON Schema](docs/presets.schema.json) for editor validation and completion.

### Upgrading a three-preset configuration

Before migrating, the app saves `presets.before-five-slots-*.json` beside the original file.

- Unmodified previous defaults (Astra Extra High / Sol Extra High / Sol High) become the five defaults above.
- Custom slots 1–3 are preserved; slots 4 and 5 are added as Sol Extra High and High.
- Existing five-slot files are unchanged.

Invalid JSON leaves the last valid settings active and adds a menu error. On a fresh launch with an invalid file, defaults remain active.
JSON cannot contain comments or trailing commas. The Command–Control modifier combination is fixed; JSON customizes each number's model, effort, and optional web label. These five keys apply model presets; they do not run arbitrary macros.

Validate syntax and slots without changing a model:

```bash
"/Applications/Codex Deck.app/Contents/MacOS/CodexUsage" \
  --validate-presets "$HOME/Library/Application Support/Codex-Usage/presets.json"
```

This command does not check your account's catalog. Runtime support is checked when applying a preset.

## 5. Read your usage

The gauges show **remaining quota**, not used quota. Only windows actually reported by Codex appear:
a weekly-only account gets one gauge and a `Usage` row. Durations appear only to distinguish multiple reported limits. There is no hard-coded monthly gauge.

- Local records are checked every 30 seconds. **Refresh Usage** scans immediately. Version 0.6.0 keeps file cursors, skips unchanged logs, and reads appended bytes instead of repeatedly parsing every full log.
- **Data as of** is the source event's timestamp, not the time you pressed Refresh.
- After a reset deadline, old data shows `--` until a new event arrives. The app never invents a 100% reset.
- If values are old or show `--`, perform work in Codex and refresh. Refreshing alone does not request server quota.

Usage events are read from `~/.codex/sessions/**/*.jsonl` and `~/.codex/archived_sessions/**/*.jsonl`.
The companion does not read `auth.json`, API keys, existing browser cookie stores, or Keychain items, and sends no telemetry or requests to an Internet service.
Direct model switching and the optional control bridge communicate with the loopback debugging endpoint. Opt-in Web Deck serves its page and limited API to paired devices on your LAN, including the active chat’s supported pending questions and approval details. Native Codex dictation uses Codex’s own transcription service; the companion’s no-telemetry statement does not describe Codex’s network activity.

The usage optimization addresses repeated whole-file `String.split`/`contains` work observed in a process sample. In a reader-only benchmark over 261 logs (353.3 MiB), initial scan wall time changed from 21.933 s to 3.608 s; unchanged follow-up scans took 0.024 s and 0.020 s. Maximum resident memory changed from 236,208,128 to 28,246,016 bytes. These are local runtime/memory measurements, **not a measurement of battery-life improvement**. See [benchmark scope](docs/model-switching.md#usage-reader-optimization).

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Shortcut does nothing | Codex must be foreground, the companion running, and the JSON saved. Remove conflicts in other shortcut tools. |
| Setup reopens / connection unavailable | Codex may have restarted without debugging. Finish current work and reconnect with Enable Direct Switching. |
| No visible Codex model control | Open a chat with its composer visible. A settings or home screen may have no target. |
| Several visible composers / unique window error | Keep one main Codex window and close additional composers or panels, then retry. |
| Model catalog is loading | Wait for Codex to finish loading the model list. |
| Unsupported model or effort | Compare JSON with your catalog. If Ultra is unavailable, explicitly choose a supported effort. |
| Confirmation required | Complete Codex's own model confirmation, then retry. |
| Unconfirmed change / timeout | Inspect model and effort before sending. The update may have happened before verification failed. |
| Presets error | Check quotes, commas, duplicate slots, and effort spelling; choose Reload Button Settings. |
| Stale quota / `--` | A new local Codex usage event is needed; see the usage section. |
| Phone cannot open Web Deck | Check the same private Wi-Fi, Mac awake, server running, macOS local-network/firewall permission, and Wi-Fi client isolation. Stop/start after an IP change. |
| Phone asks to pair again | Use a new full pairing link. Links last 5 minutes/one use; sessions last 8 hours and end on stop/restart/revocation. |
| Phone reports changed chat/preset/request | Refresh and review the target. Keep one visible saved chat; finish any Codex confirmation on the Mac. |
| No click sound | Check media volume, hardware mute, and browser sound restrictions. The deck always requests click playback, but cannot override those settings. |
| Model or mic control is disabled | Wait for the active composer's catalog; check supported effort levels and Codex's microphone permission on the Mac. |
| Mic unknown / connection lost while recording | Check Codex on the Mac and stop recording there. Disconnecting the page does not guarantee recording stops. |
| A Codex request is missing from the deck | Only supported pending approvals and user-input questions are exposed. Complete other or oversized requests on the Mac. |

If number keys select chats instead, and you do not need Codex's numeric navigation, merge
[codex-keybindings.example.json](docs/codex-keybindings.example.json) into `~/.codex/keybindings.json` **without removing unrelated entries**, then restart Codex.
Use `$CODEX_HOME/keybindings.json` if you configured a different Codex home.
The example disables chat/tab navigation 1–5 and mode navigation 1–3, including their plain Command–number or Control–number bindings.
Remove the added `null` entries to restore defaults. The companion never installs these overrides automatically.

## Update or uninstall

**Update:** choose Quit Codex Deck, replace the app in `/Applications`, then launch the new copy. When upgrading from Codex-Usage, quit the old app and move `/Applications/Codex-Usage.app` to the Trash before launching `Codex Deck.app`. The bundle identifier and existing `~/Library/Application Support/Codex-Usage` settings are retained. Check Launch at Login after moving to the renamed app.
JSON lives outside the app and is preserved. Reconnect direct switching if Codex also updated or restarted. Web Deck stops and paired phones must pair again after you start the new app's deck.

**Uninstall:** turn off Launch at Login and Open Codex Automatically, quit the companion, and move its app to Trash.
Optionally remove `~/Library/Application Support/Codex-Usage` to delete presets/backups.
Quit and normally relaunch Codex to close debugging. Restore any Codex keybindings you changed separately.

## Compatibility, development, and releases

A user confirmed **working direct switching in 0.3.1 with Codex 26.928.31416** on 2026-10-02.
Version 0.4.0 adds five presets and migration; 0.5.0 adds Codex startup at login and a simpler menu, retaining that switching path.
Version 0.6.0 adds the opt-in Web Deck and incremental usage reads. Its HTTP server, browser UI, and model bridge were checked with isolated fixtures; actual phone-to-Codex switching was not agent-tested.
Version 0.7.0 added six tactile keys and landscape/fullscreen support. Version **0.8.0** adds always-enabled bundled click audio, a percentage-only ring, the live model/effort dial, Mac dictation, and scoped pending approvals/questions. Version **0.8.1** gives the deck square white keycaps, recessed faces, a cool gray board, and matching light dialogs. Its layout and controls were checked in an offline browser from 320px portrait to 1120px desktop.
Version **0.8.2** replaces the rotary dial with a horizontal volume-style effort slider. Drag/release, touch, keyboard input, and five viewport sizes were checked in an offline browser.
Version **0.9.0** renames the app to Codex Deck and adds an inline **Models / Presets** view switch. The model keys show names only; selecting one keeps a supported effort. Browser fixtures verify view switching, model selection, slider behavior, and disconnected states.
Version **0.9.1** adds a softer original key tone, immediate pending selection, continuous slider movement, and a single latest-value effort queue. Successful model writes use the host-verified acknowledgement immediately and resume normal polling, eliminating the extra old-state repaint and read. Slow-response, failure, target-change, and keyboard cases were checked with isolated fixtures.

Version **0.9.5** centers a larger percentage ring on the Usage key and removes its caption and ellipsis. **Edit Button Settings…** now opens JSON directly from the main Mac menu, and optional `label` values customize web key names.

Version **0.9.4** simplifies preset faces to a prominent model family and smaller reasoning level, removes slot numbers and inactive dots, and keeps version labels when needed to distinguish presets. Pointer/touch slider focus has no enclosing outline; keyboard focus remains visible. The English and Korean guides now explain the preset workflow and the motivation behind the project.

Version **0.9.2** widens the frame and maps its five colors to identity-scoped native chat status, with a neutral fallback when status is unavailable. The bridge, typed payload, and responsive browser states were checked with isolated fixtures; live Codex status and physical-phone behavior were not agent-verified.
Version **0.8.3** puts the effort slider directly on the deck. Selecting a preset synchronizes the bar; moving it preserves the active model and changes only its effort. The Astra Ultra → High and Sol Extra High → High flows were verified with offline fixtures.
The 0.8.0 interface was checked in a real browser with isolated fixture data, and the integration was reviewed against static Codex source. Live Codex actions, native microphone capture, and physical-phone sound/vibration were not validated for this release. Fixture checks establish UI and contract behavior, not guaranteed compatibility with a running Codex build.
This does not establish Ultra availability for every account or coverage of every window/composer state.
The integration uses internal structure and may need repair after Codex updates.
[Implementation and verification](docs/model-switching.md) · [Micro controls and research](docs/codex-micro.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

```bash
swift test
node --test Tests/DirectSwitching/apply-preset.test.mjs
node --test Tests/WebDeck/deck.test.cjs
swift run CodexUsage --validate-presets presets.example.json
swift run CodexUsage --print
swift run CodexUsage --default-presets
swift run CodexUsage --check-direct-resources
swift run CodexUsage --check-web-resources
"/Applications/Codex Deck.app/Contents/MacOS/CodexUsage" --startup-status
./Scripts/package_app.sh
ditto -c -k --norsrc --keepParent "Codex Deck.app" Codex-Deck-macos.zip
```

`--startup-status` reports the installed app’s login, Codex auto-launch, and initial connection settings.
`--print` prints local usage, `--default-presets` prints default JSON, `--check-direct-resources` validates the switching script, and `--check-web-resources` validates the packaged Web Deck page/assets.
For browser testing without accessing Codex, run `swift run CodexUsageWebFixture` and open its printed loopback pairing URL. It serves the real Web Deck with a clearly labeled `Fixture chat`, an in-memory model catalog, simulated dictation, and sample approval/question requests. Fixture actions do not use a microphone, execute commands, or send Codex messages. Restart the fixture for a fresh pairing link.
Version 0.6.0 verification passed 60 Swift tests and 48 JavaScript tests (36 model-bridge, 12 Web Deck). Offline Chromium checks exercised all five buttons, keyboard/touch, stale/offline/disconnect states, and 320/390 px layouts without horizontal overflow. These checks do not establish live phone-to-Codex compatibility.
Set `CODEX_USAGE_OUTPUT_DIR` to package elsewhere, or `CODEX_USAGE_SIGN_IDENTITY` to use an installed signing certificate.
Pushing a `v*` tag triggers the release workflow. A normal commit does not publish a release.

MIT. An independent companion, not an official OpenAI application.
