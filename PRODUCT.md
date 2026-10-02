# Codex-Usage

<!-- impeccable:product-schema 1 -->

## Platform

web

This record covers the mobile web remote added to the existing native macOS menu bar app.

## Users and purpose

Codex users control the Mac’s active saved chat from a phone or tablet on the same Wi-Fi. The remote combines the five model presets with a live model/effort dial, Mac dictation, and scoped responses to pending approvals and user-input questions. The phone is a compact control surface rather than a general chat client.

## Operating context

The native companion remains the host and source of presets and usage. A browser pairs with that host before it can see chat details or perform actions. The active target and connection state are available by tapping Usage; errors and changed targets produce a notice. A stale target or changed request must never silently receive an action. Dictation uses the Mac microphone and stops into the composer without sending. Phone disconnection does not guarantee recording stops, so an unknown state must direct the user to check the Mac.

## Constraints

- Preserve the existing native app and JSON preset customization.
- Ship local HTML, CSS, and JavaScript without external CDNs or fonts.
- Show only state reported by the host. Fixture content belongs only in tests.
- Pairing, connection loss, changed targets, and pending actions need explicit states.
- Show only the active chat’s supported pending questions and full approval scope; allow once/deny and request-specific answers only. Unsupported or oversized requests stay on the Mac.
- Use bundled click audio on gestures without a sound toggle. Device/browser mute cannot be overridden.
- Dial/slider movement previews effort and commits on release; show only host-reported model capabilities.
- Browser fixtures establish layout and contract behavior, not live Codex or physical-phone compatibility.
- Pause polling while the page is hidden; foreground polling is no more frequent than once every five seconds and never overlaps another request.

## Working assumptions

The user's Stream Deck reference sets a compact button-grid interaction, and their white Codex Micro photo sets the visual direction: pale square keycaps with recessed circular faces, light gray framing, soft bevels, visible thickness, and charcoal labels and icons. Five model keys and one circular usage tile form a centered 3 × 2 grid in landscape or 2 × 3 grid in portrait. The keys use the largest square size that fits alongside the compact model/mic/request dock. The ring displays a percentage without a remaining caption. Keep English interface labels and physical press feedback without a persistent header, explanation, or extra branding. The native macOS menu retains its platform styling. Micro-style interactions are implemented through the existing direct bridge; no physical Micro, HID emulation, or feature-gate overrides are part of the product.
