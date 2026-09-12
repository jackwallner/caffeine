---
paths:
  - "Caffeine/Views/OnboardingView.swift"
  - "Caffeine/Views/CaffeineViews.swift"
  - "Caffeine/Views/PaywallView.swift"
  - "Caffeine/Views/SettingsView.swift"
  - "Caffeine/App.swift"
  - "Shared/Utilities/CaffeineClearance.swift"
  - "Shared/Utilities/ScreenshotConfig.swift"
---

# Caffeine: onboarding and navigation

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

## Onboarding

Five steps in `CaffeineOnboardingView`: what the app does, bedtime, the caffeine
Apple Health permission, the optional body-data permission, and one Caffeine+
step that can purchase in place.

Every step renders through the same `page(...)` builder, which is what keeps the
primary button in a pixel-identical frame across all five. Step-specific content
(a soft exit, the price disclosure, an error) goes in `aboveButton` and is
absorbed by the scrolling region; a fixed-height legal slot is reserved under the
button on every step and carries real Terms, Privacy, and Restore links on the
Caffeine+ step. Do not add anything between the button and the bottom of the
screen, and do not make a step's footer conditional on its content: both move the
button.

The Caffeine+ step is a point of purchase, so it renders the billed amount, the
3.1.2 disclosure, and that legal footer. Products failing to load falls back to
the full paywall rather than a dead button.

`-OnboardingStep <n>` (DEBUG) opens a step directly, which is the only way to
check the button frame headlessly. `-StartTab <n>` (DEBUG) opens a tab without
entering screenshot mode, which screenshot mode would empty of products.

## Navigation

Four tabs: Now, Cutoff, Timeline, and Upgrade (titled `Caffeine+` for a
subscriber). The second tab was called Body; it is named for its output now,
because the tab bar is in every screenshot and a reviewer scanning the set has
to be able to see what this app does that the category does not.

Settings is a gear in the Now toolbar, matching the rest of the fleet. There is
no Planner tab; that surface folded into the drink preview, which was already
reachable from Now.

The Now card names its own inputs. `CaffeineClearance.contributions` breaks the
running estimate into per-dose shares, the card summarises them in one line, and
`RemainingBreakdownSheet` lists them. A first launch frequently shows a non-zero
estimate before the user has tapped anything, because Apple Health already held
dietary caffeine from another app, and an unattributed number there reads as one
the app invented.

The Upgrade tab renders `CaffeinePaywallView` inline with no close button. The
tab bar stays visible over it, so nothing traps the user on a purchase screen,
and a subscriber gets a permanent place to see and manage what they bought.
