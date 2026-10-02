# Codex-Usage

<!-- impeccable:product-schema 1 -->

## Platform

web

This record covers the mobile web remote added to the existing native macOS menu bar app.

## Users and purpose

Codex users change the Mac's active chat model from a phone or tablet on the same Wi-Fi. The requested Stream Deck interaction exposes the existing five model presets. Approval decisions and question answering are outside this version's scope.

## Operating context

The native companion remains the host and source of presets and usage. A browser pairs with that host before it can see chat details or perform actions. The active target and connection state are available by tapping Usage; errors and changed targets produce a notice. A stale target must never silently receive an action.

## Constraints

- Preserve the existing native app and JSON preset customization.
- Ship local HTML, CSS, and JavaScript without external CDNs or fonts.
- Show only state reported by the host. Fixture content belongs only in tests.
- Pairing, connection loss, changed targets, and pending actions need explicit states.
- Pause polling while the page is hidden; foreground polling is no more frequent than once every five seconds and never overlaps another request.

## Working assumptions

The user's Stream Deck reference sets a compact button-grid interaction. The web remote follows the existing dark native menu and English interface labels. Five model keys and one circular usage tile fill a single viewport, primarily in landscape. The user explicitly requests physical key depth and press feedback without a persistent header or explanation.
