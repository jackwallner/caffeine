# Caffeine Tracker: Bedtime

Caffeine intake and bedtime forecasting. XcodeGen project and scheme:
`Caffeine`. Simulator lease owners: `caffeine` and `caffeine-watch`.

## Product

The app answers three separate questions:

1. How much caffeine did I consume today?
2. How much may remain in my system now and at bedtime?
3. What would another drink do before I log it?

The third question is the distinctive interaction. Every quick-log drink opens
a preview first. The user can change the drink, dose, and time, compare the
current and proposed bedtime estimates, see the dose-specific latest modeled
time, and then choose whether to log it. The same sheet edits an entry that is
already logged, so there is one place that answers "what would this drink do?".

A fourth question is answered by the Cutoff tab, and it is the one the product
is now positioned on: at what bedtime estimate did this person's own recorded
sleep actually run shorter? Nothing else in the category derives a per-person
cutoff from that person's own sleep record, so it is both the reason to choose
this app and the 4.3 answer. Every statement there is an observation about what
Apple Health recorded alongside the intake, never a causal or clinical claim.

Estimates use an exponential half-life model. They are not blood measurements,
medical advice, or safety cutoffs. The default half-life is 5 hours and the UI
also shows a 4 to 6 hour range.

## Stack and identifiers

- Swift 6, SwiftUI, SwiftData, HealthKit, WidgetKit, WatchConnectivity
- iOS 17+, watchOS 10+
- App: `com.jackwallner.caffeine`
- Widget: `com.jackwallner.caffeine.widget`
- Watch app: `com.jackwallner.caffeine.watch`
- Watch widget: `com.jackwallner.caffeine.watch.widget`
- Tests: `com.jackwallner.caffeine.tests`
- App Group: `group.com.jackwallner.caffeine`
- App Store Connect app: `6805950103`
- RevenueCat entitlement: `Caffeine+`

## Architecture

HealthKit dietary caffeine is the durable shared record. App entries are saved
as `HKQuantitySample` values in milligrams, tagged `HKMetadataKeyWasUserEntered`
and with the drink name in `HKMetadataKeyFoodType`. A denied or unavailable
HealthKit write falls back to `LocalCaffeineEntry`, which the originating device
retries on every foreground; the Now screen shows a banner naming the count so
the fallback is never silent. A successful retry deletes the queue row rather
than stamping it, so the local store stays a queue. SwiftData is a read-through
cache for widgets and complications.

The phone sends settings to the watch with WatchConnectivity. It does not queue
intake entries because HealthKit synchronizes those records.

The calculation layer is pure Swift in
`Shared/Utilities/CaffeineClearance.swift`. It owns remaining-dose calculations,
bedtime forecasts, half-life ranges, source reconciliation, daily summaries,
and latest modeled drink times. Keep model tests independent of HealthKit and
SwiftUI.

Key files:

- `Shared/Utilities/CaffeineClearance.swift`
- `Shared/Utilities/CaffeineInsights.swift`
- `Shared/Utilities/DrinkPresets.swift`
- `Shared/Services/HealthKitService.swift`
- `Shared/Services/HealthInsightsService.swift`
- `Shared/Services/CaffeineLogService.swift`
- `Shared/Services/WatchSyncService.swift`
- `Shared/Services/StoreService.swift`
- `Caffeine/Views/CaffeineViews.swift`
- `Caffeine/Views/OnboardingView.swift`
- `Caffeine/Views/PaywallView.swift`
- `Caffeine/Views/BodyInsightsView.swift`
- `Caffeine/Views/SettingsView.swift`

## Rules that hold everywhere
Condensed from the deep notes below; the reasoning behind each one lives there.
- Body insights are a separate, optional HealthKit authorization. Declining them must never affect logging or the forecast, and nothing is requested that no surface reads (5.1.3): keep the type table true when changing `HealthInsightsService.readTypes` or `BodyMetric`.
- Every onboarding step renders through the same `page(...)` builder so the primary button keeps a pixel-identical frame. Add nothing between the button and the bottom of the screen, and never make a step's footer conditional on its content.
- The cutoff verdict renders free for everyone, because it is the 4.3 answer. `PlusFeature` must not list the cutoff, and `cutoffExample` numbers must stay unmistakably labelled as an example.
- Swap iPhone screenshots with `scripts/asc-replace-iphone-screenshots.py`, never `deliver`.

## Deep notes (load on demand)
These files load automatically when you read a file matching their `paths:`. Agents that do not auto-load rules (AGENTS.md readers) should open the file for the area they are touching. Record new area-specific learnings in the matching file, not here.

| File | Covers | Read when |
|---|---|---|
| `.claude/rules/health-insights.md` | The body-insights authorization and the read-type table | `HealthInsightsService`, the Cutoff tab's data, privacy strings |
| `.claude/rules/onboarding-and-navigation.md` | Onboarding steps and the button frame; tabs, Settings, the Now card, the Upgrade tab | Onboarding, tab structure, the Now screen |
| `.claude/rules/access-model.md` | Free vs Caffeine+, the free cutoff verdict, `cutoffExample`, `PlusFeature`, store products | The paywall, locked rows, Timeline ranges, pricing |
| `.claude/rules/listing-and-localization.md` | Store name, subtitle, keywords, 50 locales, the repositioning script, screenshot replacement | Metadata, ASO scripts, screenshots |

## App Review constraints

- Never describe a modeled estimate as a measurement of caffeine in the body.
- Never claim that a displayed time guarantees sleep or safety.
- Use `may remain`, `modeled`, `estimate`, and `preference` consistently.
- Body insights describe what was recorded alongside the caffeine. Never phrase
  one as an effect caffeine caused, and never present the personal cutoff as a
  limit, a target, or a recommendation.
- A comparison with too little data says so. `CaffeineInsights` withholds a
  result rather than reporting a confident-looking number from a small or
  lopsided sample, and "no measurable difference" is a shipped answer.
- Every paywall state, including loading and failure, renders Restore, Terms of
  Use, and Privacy Policy (3.1.2). So does the Caffeine+ onboarding step.
- The buy screen is one viewport: hero, three `PlusFeature` lines, three plans,
  the billed amount, the CTA, the disclosure, and the footer. There is no full
  feature list on it; that belongs to the subscriber state. Anything added here
  pushes Restore and the two required links under the tab bar, so measure the
  bottom of the screen after changing it.
- Do not include prices, `free`, or discounts in screenshots or screenshot headers.

## Release

Run `xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh`. App Store scripts target ASC app `6805950103`.
The rejected Protein app has ASC ID `6797089333` and must not be reused for this
submission.
