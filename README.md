# Codex Deck

**English · [한국어 →](README.ko.md)**

**Your favorite Codex models, one shortcut or tap away.**

A free, open-source macOS companion. Save model + reasoning presets, switch from your keyboard or phone, and see remaining usage at a glance.

[![Watch the Codex Deck film: landscape and portrait phone controls](docs/media/codex-deck-intro-poster.jpg)](https://github.com/theconomicat/Codex-Usage/raw/refs/heads/main/docs/media/codex-deck-intro.mp4)

**[Watch the 33-second intro →](https://github.com/theconomicat/Codex-Usage/raw/refs/heads/main/docs/media/codex-deck-intro.mp4)** · English narration · [Captions](docs/media/codex-deck-intro.en.srt)

<details>
<summary>Phone layouts</summary>

<p align="center">
<img src="docs/images/codex-deck-phone.png" alt="Codex Deck in a landscape phone mockup, with five model presets, a usage ring, and a reasoning slider" width="76%" />
<img src="docs/images/codex-deck-phone-portrait.png" alt="Codex Deck in a portrait phone mockup with a two-column grid and reasoning slider" width="16%" />
</p>

<sub>Illustrative phone mockups based on the app's offline preview; sample usage.</sub>

</details>

- **Quick switching:** five presets on `⌘⌃1–5`, shared with the phone deck.
- **Phone controls:** same-Wi-Fi access, a model picker, and a reasoning slider. Mac dictation and supported questions/approvals are also available.
- **Usage:** remaining quota in the deck and your Mac menu bar.

## On your Mac

See remaining usage in the menu bar. Open the menu for model presets, settings, and automatic startup.

<p align="center">
<img src="docs/menu-bar-preview.png" alt="Codex Deck menu bar ring showing 94 percent remaining" width="185" /><br />
<img src="docs/app-menu.png" alt="Mac menu showing remaining usage, five model shortcuts, preset settings, and startup options" width="360" />
</p>

<sub>Earlier menu capture. In the current app, JSON opens directly through Edit Button Settings….</sub>

## Get started

Requires **macOS 13+**, the signed-in **Codex desktop app**, and **Swift 6** via Xcode or Command Line Tools. Build the current deck from source; older release downloads do not include these controls.

```bash
git clone https://github.com/theconomicat/Codex-Usage.git
cd Codex-Usage
./Scripts/package_app.sh
```

1. Move **Codex Deck.app** to `/Applications` and open it. Its icon appears in the menu bar.
2. Finish running Codex work, then choose **Enable Direct Switching…** and complete setup. **This restarts Codex.**
3. Open a chat with its composer visible. With Codex in front, press `⌘⌃1` to try a preset.

The usage meter works without direct switching. [Installation help →](docs/guide.md#installation)

## Use your phone

1. Keep your Mac awake and both devices on the **same trusted Wi-Fi**. Leave a saved Codex chat open.
2. In the Mac menu, choose **Web Deck… → Start Web Deck** and scan the QR code.
3. Tap a preset. Drag the bar to change reasoning effort, or tap **Models** to choose another model.

Tap the percentage ring for usage details and fullscreen. After restarting the companion, start Web Deck and pair again. [Connection help →](docs/guide.md#phone-connection)

## Make it yours

Open **Edit Button Settings…** from the Mac menu to edit JSON.

| Shortcut | Default preset |
| --- | --- |
| `⌘⌃1` | Astra · Ultra |
| `⌘⌃2` | Astra · Extra High |
| `⌘⌃3` | Astra · High |
| `⌘⌃4` | Sol 6.1 · Extra High |
| `⌘⌃5` | Sol 6.1 · High |

For example, edit the first entry to give its web button a custom name:

```json
{ "slot": 1, "model": "GPT-6 Astra", "effort": "ultra", "label": "Focus" }
```

`slot` sets the deck position and shortcut number. `model` and `effort` set the selection; optional `label` changes the web button name. Save to apply on the next shortcut or web refresh. Use **Reload Button Settings** to refresh the Mac menu immediately.

[Complete JSON example](presets.example.json) · [Configuration guide](docs/guide.md#button-settings)

## Why I built it

I kept opening menus just to check usage or change models and reasoning levels. I wanted my usual combinations ready in one action. Inspired by Codex Micro, I built a software deck for the phone I already own.

---

Model controls use Codex's internal desktop interface, so updates may affect compatibility. Phone access uses local HTTP: use trusted Wi-Fi. This is an independent project, not an official OpenAI product.

[Help & troubleshooting](docs/guide.md) · [Advanced controls](docs/codex-micro.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)
