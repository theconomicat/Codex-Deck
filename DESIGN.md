---
name: Codex Deck Web Deck
description: A light physical keypad for the Mac companion.
colors:
  page: "#e3e7e8"
  board-light: "#e0e5e6"
  board-shade: "#cbd2d4"
  key-light: "#f9fbfb"
  key-shade: "#e8edef"
  dialog: "#edf1f2"
  ink: "#262f32"
  secondary: "#515e63"
  green: "#35634c"
  selected-ink: "#294f3c"
  selected-secondary: "#415c4e"
  sage: "#dce9e1"
  warm: "#815913"
  error: "#a33d36"
  focus: "#346856"
  field-border: "#96a7ae"
  ring-track: "#bbc7c8"
  slider-track: "#cbd5d8"
  slider-thumb-border: "#98a9af"
typography:
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
  heading:
    fontSize: "1.2rem"
    fontWeight: 600
  key-model:
    fontSize: "clamp(.6875rem, 9cqw, 1.125rem)"
    lineHeight: 1.35
  key-effort:
    fontSize: "clamp(1rem, 15cqw, 2.125rem)"
    fontWeight: 650
    lineHeight: 1.15
    letterSpacing: "-.035em"
  usage:
    fontSize: "clamp(1rem, 19cqw, 2.75rem)"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-.04em"
  secondary:
    fontSize: ".8125rem"
    lineHeight: 1.5
rounded:
  slider-track: "6px"
  field: "8px"
  control: "10px"
  dock: "14px"
  dialog: "24px"
  key: "clamp(16px, 3.5vmin, 30px)"
  board: "clamp(26px, 5vmin, 44px)"
spacing:
  field-padding: "12px"
  dialog-padding: "24px"
  board-padding: "clamp(14px, 2.8vmin, 28px)"
  key-gap: "clamp(12px, 2.2vmin, 22px)"
  dock-gap: "clamp(20px, 3vmin, 28px)"
components:
  preset-key:
    backgroundColor: "{colors.key-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.key}"
    padding: "clamp(9px, 2vmin, 24px)"
  usage-key:
    backgroundColor: "{colors.key-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.key}"
    typography: "{typography.usage}"
  control-button:
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "{spacing.field-padding}"
  text-field:
    backgroundColor: "{colors.key-light}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "{spacing.field-padding}"
  dock-button:
    textColor: "{colors.ink}"
    rounded: "{rounded.dock}"
    padding: "10px 14px"
---

# Design System: Codex Deck Web Deck

## Overview

**Creative North Star: "White physical keypad"**

The user's white Codex Micro photo sets the material direction: pale square keycaps, shallow dished faces, softly beveled edges, and visible key thickness on a cool gray board. Charcoal labels and icons stay clear against the light surfaces. Depth communicates pressable controls without adding branding or a persistent header.

Scope: `Sources/CodexUsageWeb/Resources/`. The native AppKit menu retains its platform styling. These tokens describe the implemented 0.9.0 web surface; its stylesheet remains the implementation source.

**Key Characteristics:**
- Square white keys with recessed circular faces.
- Cool gray framing and structural shadows.
- Restrained sage selection with dark green indicators.
- Compact English controls using native system type.

## Colors

Cool white and gray establish the hardware material; dark green identifies selection and usage. Sage appears inside a selected key and on selected question options. Charcoal is the primary ink; medium gray is reserved for secondary labels. Keep the selected model label in selected-secondary, whose contrast was checked against the sage recess. Amber marks pending attention and reduced usage; red marks recording, errors, and low usage. Focus uses a separate dark green outline.

## Typography

Use the native system UI stack, with rem sizes for dialogs, forms, and dock controls. Key model, effort, and usage type scale within each key's container, bounded by rem minimums and maximums. Effort is the dominant label, with the model above it. Use tabular numerals for key numbers and percentages. No external font assets.

## Layout

Center the board within the viewport's safe-area padding. Six keys form a 3 × 2 grid in landscape and a 2 × 3 grid in portrait. The board calculation reserves its padding, gaps, effort slider and controls before choosing the largest square key size that fits. In landscape the controls sit in a column to the right of the keys and the slider spans both columns below. Portrait places the slider and then the dock below the keys.

The portrait dock is 52px high (44px below 650px viewport height). The effort row reserves 84px. Landscape at 440px height or less uses 12px board padding, 10px key gaps, a 14px row gap, a 96px control column and a 66px effort row with endpoint labels hidden. The toggle reads Models or Presets at every width; below a 350px board container hide its icon, and below 290px hide the Requests and microphone icons. Keep accessible names intact. Dialogs may scroll internally on short screens. Active-deck notices sit at the top so the Mac mic control stays available.

## Elevation & Depth

Use gradients and structural shadows to distinguish the board, raised key edges, and circular recesses. Keys have two gray lower edges and a soft grounded shadow; the pale highlight belongs on the upper edge. The effort slider shares this material: a recessed 12px track and a raised white 34px thumb within a 48px touch area (44px in short landscape). The dark green fill and effort label follow the drag without animation. Press reduces the shadow and, for pointer input, moves the key down 4px over 100ms. Keyboard input and reduced motion avoid movement. Exact shadows and motion are recorded in `.impeccable/design.json`.

## Shapes

Keys retain a square silhouette with softly rounded corners. Each dished face is a circle at 80% of key width. The board has broader corners than the keys. Dock controls are shallow rounded rectangles, and form fields use the tighter field radius. Keep touch controls at least 44px.

## Components

- **Preset keys:** model above effort, small key number and indicator at the top. Confirmed selection changes the recess, label, border, and LED; pending uses amber. Preserve selected, busy, disabled, and focus states. Never show success before host confirmation.
- **Usage key:** a circular track with the percentage only; no “remaining” caption. Unknown, expired, or offline data uses an em dash. Opens the native dialog for the active chat, usage details, fullscreen, refresh, and disconnect.
- **Model controls:** an inline catalog of model-name keys toggled by Models / Presets and an always-visible horizontal range input directly on the deck, labeled with the active model and effort. Keep native touch and keyboard semantics. Preset confirmation synchronizes the slider. Pointer movement previews and release changes only the active model’s effort; saved presets remain unchanged. Choosing a different model applies a supported effort.
- **Dock and requests:** Model, Mac mic, and a Requests control only when supported requests are waiting. Recording has an explicit red state. Request dialogs show relevant options and text fields with clear Allow once/Deny treatments.
- **Feedback:** visible focus outline, dismissible screen-reader-announced notices, short bundled click audio and supported-device vibration after gestures. Sound has no page toggle; hardware/browser mute remains authoritative. No idle animation or continuous audio.

## Do's and Don'ts

- **Do** preserve square keys, readable labels, and visible keyboard focus across supported viewport sizes.
- **Do** keep existing model, dictation, request, pairing, and validation behavior intact when changing appearance.
- **Do** use the material shadows to explain pressable controls.
- **Don't** add decorative branding, a persistent header, or explanatory copy to the main deck.
- **Don't** use color alone to report recording, selection, pending actions, or failure.
- **Don't** treat a lost connection as confirmation that the Mac microphone stopped.

The model catalog occupies the preset grid’s existing footprint with two columns in portrait and four in landscape. Its white keys contain only model names, with confirmed selection indicated by a sage face and aria-pressed. Larger catalogs scroll within the grid. The original grid is inert while hidden. Models / Presets changes the view instantly without animation or a model write; Escape returns to Presets.
