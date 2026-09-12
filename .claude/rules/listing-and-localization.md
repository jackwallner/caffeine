---
paths:
  - "fastlane/**/*"
  - "scripts/asc-*.py"
  - "scripts/aso-*"
  - "scripts/astro-*"
  - "Screenshots/**/*"
  - "aso-plan.md"
  - "docs/*.html"
---

# Caffeine: store listing, ASO and localization

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

### Store listing and localization

- App Store name: `Caffeine Tracker: Bedtime`.
- Subtitle: `Your Sleep Sets The Cutoff`. It carries the differentiator, because
  the name cannot: `Caffeine Cutoff` sits too close to the shipping competitor
  `Caffeine Curfew` and would argue Apple's 4.3 case for them.
- Keywords: `coffee,tea,intake,calculator,energy,drink,log,timer,metabolism,widget,watch,mg,half-life,decaf,focus`.
  `sleep` and `cutoff` moved into the subtitle, which freed both slots.
- All 50 locales carry native copy. Name and subtitle target 24-30 characters
  and keywords 94-100, except `ja`, `ko`, `zh-Hans`, and `zh-Hant`, where a word
  is one or two characters and the floor would only buy filler; those keep
  Apple's ceiling alone on all three fields. `asc-readiness.py` and
  `asc-upload-localizations.py` both encode that exception. The keyword half of
  it was missing until the 4.3 rework, so those four storefronts silently
  skipped every localization upload.
- `scripts/aso-apply-cutoff-repositioning.py` rewrites the positioning lines of
  all 49 non-en-US descriptions from `aso-cutoff-strings.json`. The localized
  files share a fixed 40-line shape, so it addresses lines by index rather than
  matching native prose. Apple's description ceiling is 4000 characters and the
  Romance and Dravidian storefronts sit within ~100 of it, so any line that
  grows there has to be paid for by shortening another.
- `scripts/asc-replace-iphone-screenshots.py` swaps the iPhone set in place and
  leaves the Watch set alone. Use it instead of `deliver`, which walks the whole
  tree and has double-uploaded on retry.
