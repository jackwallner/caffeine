# Caffeine Tracker: Bedtime

An iPhone and Apple Watch app for logging caffeine, estimating what may remain,
and previewing the bedtime impact of another drink before logging it.

## What makes it different

Most caffeine trackers begin after a drink is logged. This app puts the model
before the action. Tap a preset, adjust its dose and time, compare the existing
and proposed bedtime estimates, then decide whether to log it.

The app also provides:

- consumed caffeine today
- a modeled current amount
- a bedtime forecast with a visible 4 to 6 hour half-life range
- a dose-specific latest modeled time against a personal bedtime preference
- Apple Health import, export, and per-source controls
- iPhone widgets, Watch complications, and wrist logging
- seven days of free history, with full trends in Caffeine+

The model is an estimate, not a blood measurement, medical recommendation, or
guarantee about sleep.

## Model

For a dose `D`, elapsed time `t`, and selected half-life `h`:

```text
remaining = D * 0.5^(t / h)
```

Each caffeine sample is decayed independently and then summed. The default
half-life is 5 hours. A 4 to 6 hour range communicates normal uncertainty rather
than presenting one number as exact.

## Architecture

- HealthKit dietary caffeine is the durable intake record.
- SwiftData caches reconciled values for widgets and complications.
- Local fallback entries preserve logs when HealthKit writes are unavailable.
- WatchConnectivity mirrors settings from iPhone to Watch.
- The pure calculation layer has no HealthKit or SwiftUI dependency.
- RevenueCat provides Caffeine+ entitlement state.

## Build

```sh
xcodegen generate
agent-sim checkout caffeine
xcodebuild test \
  -project Caffeine.xcodeproj \
  -scheme Caffeine \
  -destination 'id=<LEASED_UDID>'
agent-sim checkin caffeine
```

Never build against a named simulator destination. See `CLAUDE.md` and the
shared `ios-dev` skill for signing and release conventions.

## Targets

| Target | Bundle ID |
| --- | --- |
| Caffeine | `com.jackwallner.caffeine` |
| CaffeineWidget | `com.jackwallner.caffeine.widget` |
| CaffeineWatch | `com.jackwallner.caffeine.watch` |
| CaffeineWatchWidget | `com.jackwallner.caffeine.watch.widget` |
| CaffeineTests | `com.jackwallner.caffeine.tests` |

App Group: `group.com.jackwallner.caffeine`

## Store

Core tracking and forecasting are free. Caffeine+ adds full history, trends,
custom quick-preview amounts, and a bedtime reminder.

The privacy policy, support page, and terms are in `docs/` and are served by
GitHub Pages.
