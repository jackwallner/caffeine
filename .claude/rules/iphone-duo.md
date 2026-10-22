---
paths:
  - "Caffeine/App.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
---

# Caffeine: iPhone Duo (2026-10-22)

- Unfolded (regular width, at least 720 pt), `CaffeineTabView` keeps the
  `TabView` (Now, Timeline, Upgrade, and its tab bar) on the leading side of the
  fold and puts Your Cutoff in its own pane on the trailing side. The Cutoff tab
  drops out of the tab bar while split, and a request for tab 1 lands on Now.
  The pairing is deliberate: the bedtime forecast on Now is read against the
  cutoff from this person's own nights, which is the product's positioning.
- Pane edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split. `UnfoldedSplit` holds the
  math and is unit-tested; portrait unfolded (669 pt) and every compact width
  keep the single column, so the folded outer display is unchanged.
- Folding only moves the `TabView`'s frame, so Now, Timeline and Upgrade keep
  their state. Your Cutoff moves between a tab and the pane, so its scroll
  position resets on fold or unfold; its data lives in `HealthInsightsService`.
- Each pane gets `horizontalSizeClass = .compact`, so it lays out as on a phone.
  Never add a device-name check.
- Captures: one launch gives one inner and one outer PNG, so each surface is its
  own `gh-sim launch --device 'iPhone Duo'` run with
  `-SeedScreenshotData -DemoPro -ScreenshotTab <n>` (or `-PreviewSnapshot`).
  `--url` routes are unusable: iOS 27 answers `simctl openurl` with an
  "Open in" alert that stays over every later shot.
