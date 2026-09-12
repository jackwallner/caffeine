---
paths:
  - "Caffeine/Views/PaywallView.swift"
  - "Caffeine/Views/BodyInsightsView.swift"
  - "Caffeine/Views/CaffeineViews.swift"
  - "Shared/Services/StoreService.swift"
  - "Shared/Utilities/ConversionCopy.swift"
  - "Shared/Utilities/CaffeineInsights.swift"
  - "Caffeine.storekit"
  - "CaffeineTests/PaywallFunnelTests.swift"
---

# Caffeine: the access model

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

## Access model

Logging, previewing a drink, current and bedtime estimates, Apple Health source
controls, widgets, complications, and seven days of history are free.

Caffeine+ unlocks the Cutoff tab's metric-by-metric comparisons, full history
and trends, editable quick-log drinks, and the bedtime reminder. A lapsed
subscriber keeps saved preset values, but cannot edit them until access is
restored. The locked range in Timeline shows a lock panel; it never renders
seven days under a `30D` label.

The cutoff verdict is free, and that is a reversal. It was moved behind the
lock because meeting the feature as the words "No clear difference" gave people
no reason to want more of it. Apple rejected 1.0 under 4.3, and the decisive
fact was that a reviewer on a fresh install could not reach the one screen that
distinguishes this app from a half-life calculator: it was behind both a
purchase and 21 nights of history. Conversion tuning does not get to hide the
differentiator. The verdict renders for everyone; the comparisons underneath it
are still Caffeine+, pitched with the person's real findings rendered blurred.
Nothing under that blur is invented; it is the same view Caffeine+ unblurs.

While the first 21 nights accumulate, `cutoffExample` renders a fixed worked
example under the progress bar, headed "EXAMPLE OF THE FINDING - NOT YOUR DATA".
It exists so the feature is legible on day one, to a new user and to a reviewer
who will never have 21 nights. Its numbers are constants and must stay
unmistakably labelled; the moment it could read as a measurement of the person
looking at it, it is a 1.4.1 problem instead of an explanation.

`PlusFeature` is the single list of what Caffeine+ includes. Paywall bullets and
in-app locked rows both read from it so they cannot drift, and it must not list
the cutoff: a paywall bullet selling something that renders free is its own
3.1.2 problem.

Store products:

- `com.jackwallner.caffeine.monthly`, $5.99 with a one-week trial
- `com.jackwallner.caffeine.yearly`, $29.99 with a one-week trial
- `com.jackwallner.caffeine.pro.lifetime`, $59.99
