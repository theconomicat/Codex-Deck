# Codex-Usage

[한국어 사용 설명서](README.ko.md)

A macOS menu bar companion for **remaining Codex quota** and **model preset shortcuts**.
Change the current chat's model and reasoning effort together without opening the model picker. No Stream Deck hardware is required.

## Preview

### App menu

<img src="docs/app-menu.png" alt="Codex-Usage menu grouping five shortcuts with separate preset settings and automatic launch options" width="560" />

User-provided screenshot of the running 0.5.0 app. All five shortcuts form one group; preset editing lives in a separate submenu. A single weekly quota is labeled `Usage` instead of `1w`.

### Menu bar usage

<img src="docs/menu-bar-preview.png" alt="Codex-Usage menu bar showing 94 percent remaining in a single green quota ring" width="185" />

User-provided screenshot of a weekly-only account: the green ring shows 94% remaining. The adjacent Codex icon belongs to Codex itself. Values update from local Codex usage events.

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

1. Download `Codex-Usage-macos.zip` from the desired [release](https://github.com/theconomicat/Codex-Usage/releases).
   The five presets described here require **0.4.0 or newer**. If that version is not published yet, build from source below.
2. Unzip and move `Codex-Usage.app` into **`/Applications`**.
3. Quit an older running copy with **Quit Codex-Usage** before opening the new app.
4. Click the Codex-Usage icon in the macOS menu bar. It is a menu bar app; a persistent Dock window is not expected.

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

Move the generated `Codex-Usage.app` to `/Applications` and launch it. Quit the old copy before replacing an existing installation.

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

### Menu reference

| Item | Action |
| --- | --- |
| Refresh Usage | Scan local usage records immediately. |
| Five model presets | Apply that preset to the current chat; Codex must be foreground. |
| Enable Direct Switching… | Set up the connection by restarting Codex. |
| Model Presets → Edit Presets… | Open the JSON configuration. |
| Model Presets → Reload Presets | Read saved JSON and refresh the menu. |
| Launch at Login | Toggle companion startup at login. |
| Open Codex Automatically | Open a closed Codex app with direct switching when the companion starts; requires initial setup. |
| Quit Codex-Usage | Quit the companion. To close debugging too, quit Codex and relaunch it normally. |

## 4. Customize your models

1. Choose **Model Presets → Edit Presets…**.
2. Change `model` and `effort` in a text editor. Use `slot` to choose the shortcut number.
3. Save. The next shortcut automatically reloads the file. Choose **Model Presets → Reload Presets** to update the menu immediately.

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
| `slot` | Include numbers `1` through `5` exactly once. `slot: 4` means `⌘⌃4`. Array order does not matter. |
| `model` | A display name or ID from your Codex catalog, such as `GPT-6 Astra`, `gpt-6-astra`, `GPT-6.1 Sol`, or `gpt-6.1-sol`. |
| `effort` | A supported value: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, or `ultra`. |

**Extra High is `xhigh`**; Ultra is `ultra`. Do not enter `extra high` in JSON.
Model matching ignores the `GPT-` prefix, case, spacing, and punctuation, but must identify exactly one catalog entry.
`GPT-6 Sol` and `GPT-6.1 Sol` are different models.

For example, replace only slot 5's entry to use GPT-6 Luna / High:

```json
{ "slot": 5, "model": "GPT-6 Luna", "effort": "high" }
```

To restore defaults, replace your file with the complete JSON above or [presets.example.json](presets.example.json), then save.
Use the [JSON Schema](docs/presets.schema.json) for editor validation and completion.

### Upgrading a three-preset configuration

Before migrating, the app saves `presets.before-five-slots-*.json` beside the original file.

- Unmodified previous defaults (Astra Extra High / Sol Extra High / Sol High) become the five defaults above.
- Custom slots 1–3 are preserved; slots 4 and 5 are added as Sol Extra High and High.
- Existing five-slot files are unchanged.

Invalid JSON leaves the last valid settings active and adds a menu error. On a fresh launch with an invalid file, defaults remain active.
JSON cannot contain comments or trailing commas. The Command–Control modifier combination is fixed; JSON customizes each number's model and effort.

Validate syntax and slots without changing a model:

```bash
/Applications/Codex-Usage.app/Contents/MacOS/CodexUsage \
  --validate-presets "$HOME/Library/Application Support/Codex-Usage/presets.json"
```

This command does not check your account's catalog. Runtime support is checked when applying a preset.

## 5. Read your usage

The gauges show **remaining quota**, not used quota. Only windows actually reported by Codex appear:
a weekly-only account gets one gauge and a `Usage` row. Durations appear only to distinguish multiple reported limits. There is no hard-coded monthly gauge.

- Local records are checked every 30 seconds. **Refresh Usage** scans immediately.
- **Data as of** is the source event's timestamp, not the time you pressed Refresh.
- After a reset deadline, old data shows `--` until a new event arrives. The app never invents a 100% reset.
- If values are old or show `--`, perform work in Codex and refresh. Refreshing alone does not request server quota.

Usage events are read from `~/.codex/sessions/**/*.jsonl` and `~/.codex/archived_sessions/**/*.jsonl`.
The companion does not read `auth.json`, API keys, browser cookies, or Keychain items, and sends no telemetry or external network requests.
Direct model switching communicates only with the local debugging endpoint.

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
| Presets error | Check quotes, commas, duplicate slots, and effort spelling; choose Reload Presets. |
| Stale quota / `--` | A new local Codex usage event is needed; see the usage section. |

If number keys select chats instead, and you do not need Codex's numeric navigation, merge
[codex-keybindings.example.json](docs/codex-keybindings.example.json) into `~/.codex/keybindings.json` **without removing unrelated entries**, then restart Codex.
Use `$CODEX_HOME/keybindings.json` if you configured a different Codex home.
The example disables chat/tab navigation 1–5 and mode navigation 1–3, including their plain Command–number or Control–number bindings.
Remove the added `null` entries to restore defaults. The companion never installs these overrides automatically.

## Update or uninstall

**Update:** choose Quit Codex-Usage, replace the app in `/Applications`, then launch the new copy.
JSON lives outside the app and is preserved. Reconnect direct switching if Codex also updated or restarted.

**Uninstall:** turn off Launch at Login and Open Codex Automatically, quit the companion, and move its app to Trash.
Optionally remove `~/Library/Application Support/Codex-Usage` to delete presets/backups.
Quit and normally relaunch Codex to close debugging. Restore any Codex keybindings you changed separately.

## Compatibility, development, and releases

A user confirmed **working direct switching in 0.3.1 with Codex 26.928.31416** on 2026-10-02.
Version 0.4.0 adds five presets and migration; 0.5.0 adds Codex startup at login and a simpler menu, retaining that switching path.
This does not establish Ultra availability for every account or coverage of every window/composer state.
The integration uses internal structure and may need repair after Codex updates.
[Implementation and verification](docs/model-switching.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

```bash
swift test
node --test Tests/DirectSwitching/apply-preset.test.mjs
swift run CodexUsage --validate-presets presets.example.json
swift run CodexUsage --print
swift run CodexUsage --default-presets
swift run CodexUsage --check-direct-resources
/Applications/Codex-Usage.app/Contents/MacOS/CodexUsage --startup-status
./Scripts/package_app.sh
ditto -c -k --norsrc --keepParent Codex-Usage.app Codex-Usage-macos.zip
```

`--startup-status` reports the installed app’s login, Codex auto-launch, and initial connection settings.
`--print` prints local usage, `--default-presets` prints default JSON, and `--check-direct-resources` validates the packaged script.
Set `CODEX_USAGE_OUTPUT_DIR` to package elsewhere, or `CODEX_USAGE_SIGN_IDENTITY` to use an installed signing certificate.
Pushing a `v*` tag triggers the release workflow. A normal commit does not publish a release.

MIT. An independent companion, not an official OpenAI application.
