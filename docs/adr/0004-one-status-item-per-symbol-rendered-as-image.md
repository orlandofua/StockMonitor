# 4. One status item per symbol, rendered as a custom image

Date: 2026-11-17

## Status

Accepted

## Context

The display should match the style of the Stats app (a small label above a large value) combined with the Stocks app's colored change badge:

```
BZ=F
92.16 [-0.28]
```

A status item's button can show either an attributed title or an image. An attributed title cannot draw a rounded, colored badge, and two lines of text in a title do not fit the menu bar height reliably. The user may also track several symbols, and each should be clickable on its own, as in Stats.

## Decision

- Create one `NSStatusItem` per symbol, in list order (the first symbol is leftmost).
- Draw each item's content as an `NSImage` in `TickerImage.make`: an 8 pt symbol label on top, a 12.5 pt semibold monospaced-digit price below, and a rounded green or red badge with the change beside the price. Text is positioned by baseline so it fits both 22 pt and 24 pt (notched) menu bars.
- Draw the image with a drawing handler and dynamic system colors (`labelColor`), so the text follows the menu bar's light or dark appearance at draw time. The image is not a template image, because the badge must keep its color.
- Each item has its own menu, rebuilt on open (`menuNeedsUpdate`), with quote details and app actions.

## Consequences

- The look is fully under our control and matches the reference apps.
- Many symbols take a lot of menu bar space. macOS hides items that do not fit, especially on notched displays.
- Layout constants live in `TickerImage.swift`. Changing fonts or sizes needs a visual check in both light and dark menu bars.
- Adding a symbol rebuilds all items so their order matches the list.
