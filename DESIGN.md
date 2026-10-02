# Web remote design

Scope: `Sources/CodexUsageWeb/Resources/`. The native AppKit menu retains its platform styling.

The remote is an operating surface for repeated model changes. Use the existing app's dark graphite character and green usage accent, expressed as a compact deck of tactile keys. It is not a marketing page.

## Tokens

- Background: `#141615`; raised keys: `#242724`; input surface: `#1b1e1b`.
- Text: `#f3f3ee`; secondary: `#b5bbb3`; muted: `#9ca69a`.
- Selection and connected state: `#b7e3a1`; pending attention: `#e8c58a`; errors: `#ffb4a8`.
- Borders: `#3f463d`; focus: `#d6efc8`.
- Type: system UI, 16px base, fixed rem sizes. Tabular numerals for key numbers.
- Spacing: 4, 8, 12, 16, 24, 32, 48px. Keys use a 12px radius; controls use 8px.

## Composition and behavior

Show product name and connection status, then the active chat and usage, then five model keys. Phone layouts use two columns; wider layouts use three or five. Each key has its slot number, model, effort, and selected/applying state. Refresh and device disconnection remain secondary controls below the deck.

Use native buttons and semantic headings. Keep focus visible and touch controls at least 44px. Preserve focus across refreshes unless the preset definitions change. Never indicate success before the host confirms it.

No entrance motion or decorative animation. Pointer press may scale a key slightly; keyboard input and reduced-motion mode remain still. Color and text communicate all states together. Error recovery stays inline.
