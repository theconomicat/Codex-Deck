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

Fill the dynamic viewport with six physical-style keys: five model presets and a remaining-usage ring. Landscape is 3 × 2; portrait is 2 × 3. No persistent header, footer, chat title, or hints. The usage key opens a native dialog for the active chat, usage details, fullscreen, sound, refresh, and disconnect. Pairing and failures appear only when needed.

Use native buttons and semantic headings. Keep focus visible and touch controls at least 44px. Preserve focus across refreshes unless the preset definitions change. Never indicate success before the host confirms it.

Graphite bevels and a dark lower edge express depth. A confirmed selection has a green face and indicator; pending uses amber. Press moves down 4px for 90ms; reduced motion removes movement. A short synthesized click and supported-device vibration occur only after a user gesture. Sound can be muted, audio suspends after each press, and there are no idle animations. Errors and changed-target notices are dismissible and screen-reader announced. The usage ring shows an em dash for absent, expired, or offline data.
