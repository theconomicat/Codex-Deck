# Codex Deck

<!-- impeccable:product-schema 1 -->

## Platform

web

This record covers the mobile web remote added to the existing native macOS menu bar app.

## Users and purpose

Codex users control the Mac’s active saved chat from a phone or tablet on the same Wi-Fi. The remote combines the five model presets with an inline model catalog and horizontal effort slider, Mac dictation, and scoped responses to pending approvals and user-input questions. The phone is a compact control surface rather than a general chat client.

## Operating context

The native companion remains the host and source of presets and usage. A browser pairs with that host before it can see chat details or perform actions. The active target and connection state are available by tapping Usage; errors and changed targets produce a notice. A stale target or changed request must never silently receive an action. Dictation uses the Mac microphone and stops into the composer without sending. Phone disconnection does not guarantee recording stops, so an unknown state must direct the user to check the Mac.

## Constraints

- Preserve the existing native app and JSON preset customization.
- Ship local HTML, CSS, and JavaScript without external CDNs or fonts.
- Show only state reported by the host. Fixture content belongs only in tests.
- Pairing, connection loss, changed targets, and pending actions need explicit states.
- Show only the active chat’s supported pending questions and full approval scope; allow once/deny and request-specific answers only. Unsupported or oversized requests stay on the Mac.
- Use bundled click audio on gestures without a sound toggle. Device/browser mute cannot be overridden.
- The horizontal slider is always visible on the main deck. It follows confirmed presets and changes only the active model’s effort on release; show only host-reported model capabilities.
- Show requested selections immediately as pending and commit host acknowledgements without an old-state repaint. Keep the slider responsive during a write, coalescing further releases to one trailing value for the same chat. Discard queued input on failure, target change, or page close.
- Browser fixtures establish layout and contract behavior, not live Codex or physical-phone compatibility.
- Pause polling while the page is hidden; foreground polling is no more frequent than once every five seconds and never overlaps another request.

## Working assumptions

The user's Stream Deck reference sets a compact button-grid interaction, and their white Codex Micro photo sets the visual direction: pale square keycaps with recessed circular faces, light gray framing, soft bevels, visible thickness, and charcoal labels and icons. Five model keys and one circular usage tile form a centered 3 × 2 grid in landscape or 2 × 3 grid in portrait. The keys use the largest square size that fits alongside the effort bar and compact model/mic/request dock. In landscape the dock sits to the right of the keys and the slider spans the bottom; portrait keeps the slider and dock below the keys. The larger ring sits centered in its square key and displays only a percentage, with no Usage caption, ellipsis, or second recessed circle. Tapping it opens usage details. Button settings open directly from the Mac menu as JSON: slot maps position and shortcut, model and effort select the combination, and optional label customizes the web name. Keep English interface labels and physical press feedback without a persistent header, explanation, or extra branding. The native macOS menu retains its platform styling. Micro-style interactions are implemented through the existing direct bridge; no physical Micro, HID emulation, or feature-gate overrides are part of the product.

The Models button replaces preset keys with model-name buttons and becomes Presets to return. No sets or arbitrary Mac shortcuts. Returning changes only the view. The slider stays visible in both views; model selection preserves the current effort when supported, otherwise High or the first supported effort.

Preset faces prioritize the model family (Astra, Sol) above a smaller explicit reasoning label. Hide printed slot numbers and inactive LED dots. Show a version only when distinct models in the preset group share that family; retain full custom names and full model identities in the catalog and accessible labels. This is a display change, never a model ID or configuration migration.
