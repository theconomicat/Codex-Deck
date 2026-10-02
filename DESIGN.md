# Web remote design

Scope: `Sources/CodexUsageWeb/Resources/`. The native AppKit menu retains its platform styling.

The remote is an operating surface for model changes, Mac dictation, and responses to the active chat’s pending requests. Use the existing app's dark graphite character and green usage accent, expressed as a compact deck of tactile keys. It is not a marketing page.

## Tokens

- Background: `#141615`; raised keys: `#242724`; input surface: `#1b1e1b`.
- Text: `#f3f3ee`; secondary: `#b5bbb3`; muted: `#9ca69a`.
- Selection and connected state: `#b7e3a1`; pending attention: `#e8c58a`; errors: `#ffb4a8`.
- Borders: `#3f463d`; focus: `#d6efc8`.
- Type: system UI, 16px base, fixed rem sizes. Tabular numerals for key numbers.
- Spacing: 4, 8, 12, 16, 24, 32, 48px. Keys use a 12px radius; controls use 8px.

## Composition and behavior

Fill the main viewport with six physical-style keys: five model presets and a remaining-usage ring. Landscape is 3 × 2; portrait is 2 × 3. A compact dock provides Model & effort, Mac mic, and a Requests button only when supported requests are waiting. No persistent page header, chat title, or explanatory copy. The usage ring contains the percentage only, with no “remaining” caption. The usage key opens a native dialog for the active chat, full usage details, fullscreen, refresh, and disconnect. Pairing and failures appear only when needed.

Model & effort uses the host’s live catalog and supported effort levels. The visual dial and native range input stay synchronized; pointer movement previews and release commits. Keep the native slider keyboard-accessible. Model choice applies immediately with a supported effort. Pending-request dialogs show the target, complete details, and only the relevant options or text fields; never add a general message composer or blanket access switch.

Use native buttons and semantic headings. Keep focus visible and touch controls at least 44px. Preserve focus across refreshes unless the preset definitions change. Never indicate success before the host confirms it.

Graphite bevels and a dark lower edge express depth. A confirmed selection has a green face and indicator; pending uses amber. Press moves down 4px for 90ms; reduced motion removes movement. A bundled media click and supported-device vibration occur after a user gesture, with a short synthesized fallback if media playback fails. Sound is always enabled in the page, with no mute control; browser and hardware mute remain authoritative. Playback is brief, fallback audio suspends after each press, and there are no idle animations. Errors and changed-target notices are dismissible and screen-reader announced. The usage ring shows an em dash for absent, expired, or offline data.

Mac mic has distinct idle, recording, unavailable, and unknown states. Stop inserts a transcript without sending. Connection loss must not show the microphone as safely off: tell the user to check the Mac. Requests remain scoped to the displayed chat and fingerprint; preserve entered answers across unchanged refreshes and reject changed requests.
