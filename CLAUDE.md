# Protein Tracker — Project Guide

Pure protein tracking: one gram target, one number, wrist-first. XcodeGen
project/scheme: `Protein`, sim lease owner `protein` (`protein-watch` for a
paired-watch lease).

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency)
- HealthKit (`dietaryProtein`, read **and** write), SwiftData in an App Group,
  WidgetKit, WatchConnectivity
- XcodeGen (`project.yml`). Targets: iOS 17+, watchOS 10+
- RevenueCat, entitlement `pro`, tier branded **Protein+**

## Targets / bundle IDs
- `Protein` — `com.jackwallner.protein`
- `ProteinWidget` — `com.jackwallner.protein.widget`
- `ProteinWatch` — `com.jackwallner.protein.watch`
- `ProteinWatchWidget` — `com.jackwallner.protein.watch.widget`
- `ProteinTests` — `com.jackwallner.protein.tests`
- App Group `group.com.jackwallner.protein`
- ASC record `6797089333`

## Architecture

**HealthKit is the single source of truth, including for our own entries.**
This is the one decision the rest of the app hangs off (`docs/plan.md` §4):

```
log 30g on wrist  →  HKQuantitySample(.dietaryProtein, 30g, source = us)
today's total     =  sum of ALL dietaryProtein samples
                     WHERE source ∈ (us + user-selected external sources)
SwiftData         =  read-through cache, for the widgets/complication only
```

Consequences, all deliberate:
- **No WatchConnectivity queue for entries.** HealthKit syncs across the paired
  devices, so a wrist tap reaches the phone with no write ordering, no retry,
  and no "logged while the phone was asleep" case. WC carries *settings only*
  (target, presets, entitlement), phone → watch, via `applicationContext`.
- **Double counting is not a special case.** One sum over one source set.
- **Write auth can be denied**, and HealthKit says so honestly. `ProteinLogService`
  falls back to `LocalProteinEntry` rows, which are summed alongside the
  HealthKit samples and migrated in later by `retryPendingLocalEntries()`. This
  path ships in v1; do not let it rot.
- Reads use an `HKSampleQuery` grouped by source, **not** a statistics
  collection — the Sources screen needs per-source grams *and* timestamps, and
  a statistics sum cannot answer "which app, and when".

`ProteinReconciliation` is pure (no HealthKit, no SwiftUI) and carries the
multi-source rules. It is the only part verifiable without a real device and
two food loggers, so it is the part that is unit tested hard.

Key files:
- `Shared/Utilities/ProteinReconciliation.swift` — totals, per-source rows, duplicate risk
- `Shared/Services/HealthKitService.swift` — read/write/auth/observer/cache
- `Shared/Services/ProteinLogService.swift` — log, undo, write-denied fallback
- `Shared/Services/WatchSyncService.swift` — settings mirror, phone → watch
- `Shared/Utilities/ProteinTargets.swift` — the audience fork's target maths

## Free vs Protein+

Free is **read-only**: target, today's total imported from Apple Health, the
iPhone widget, the Watch complication, 7 days of history. Protein+ is the
**logging** half: adding grams anywhere, the quick-add presets, the source
picker, the evening reminder, 30 days of history.

The complication keeps updating for free users on purpose. It costs nothing and
it is what keeps the app on the wrist while they reconsider; the graveyard
clones in `aso-plan.md` collect one-star reviews for taking everything away.

Access model: **one StoreKit trial**, decided 2026-08-04. The offer sheet is the
final onboarding step and StoreKit owns the 7 days. There is no separate local
trial window — `docs/plan.md` §7 flagged the stacked alternative and it was
rejected.

## App-specific notes
- **Review funnel trigger**: the third distinct day the user hits their target
  (`ReviewPromptTracker.recordTargetHit`), never before. App Store ID 6797089333.
- **App Review 1.4.1**: the lifter / GLP-1 / post-bariatric stories stay "track
  the target you were given". Never "we set your medical target". A unit test
  (`testReasonCopyMakesNoMedicalClaims`) fails the build on treat/cure/diagnose/
  prescribe/prevent appearing in the audience copy — keep it that way.
- **Positioning is anti-AI on purpose.** No photo estimation, no food database,
  no calories, no macros beyond protein. That is the product, not a backlog.
- Never put `calorie`, `macro`, `AI`, or `scanner` in the subtitle — those steer
  Apple toward difficulty 73-81 SERPs and contradict the position (`aso-plan.md` §5).
- Watch layout must fit above the fold on a 41mm (224pt) screen. There is no
  navigation title for exactly this reason, and Undo takes the "Other" slot
  rather than adding a fourth row.
- `ScreenshotFixtures` (DEBUG) backs `-SeedScreenshotData` / `-ScreenshotTab N`
  / `-PaywallSnapshot`. `StoreService` hydrates the paywall on the simulator from
  StoreKit Testing, falling back to `TestStoreProduct` fixtures, so the real
  paywall renders headlessly without ever configuring the prod RevenueCat key.

## Release state (2026-08-04)

- TestFlight build 2 is uploaded and VALID.
- ASC products are all **READY_TO_SUBMIT**: `.monthly` $1.99, `.yearly` $14.99
  (both with a 1-week free trial in 175 territories and the Vitals PPP
  overrides), `.pro.lifetime` $29.99.
- **RevenueCat is not wired up yet, and this is the one thing blocking a real
  purchase.** The `default` offering exists but has **zero packages**, so a
  device build shows "Protein+ Plans Unavailable". In the RC dashboard for the
  Protein project: add the three App Store products, attach them to the `pro`
  entitlement, and put them in `default` as `$rc_monthly`, `$rc_annual`, and
  `$rc_lifetime`. There is no management key for this project on disk, so it
  cannot be scripted from here.
- The ASC record is still named `Protein App Placeholder`, and the app name,
  genre (Health & Fitness), age rating, review notes, and the Regulated Medical
  Device declaration (UI-only, not in the API) are untouched. That is a
  deliberate submission pass, not an oversight.
- `docs/` is ready for GitHub Pages, but the repo is local-only. The privacy,
  terms, and support URLs in the metadata will 404 until the repo exists on
  GitHub, is public, and has Pages pointed at `main` `/docs`. App Review will
  reject on a dead privacy URL.

## Open risks (carried from `docs/plan.md` §8)
1. **The HealthKit import test has never been run on a real device.** Whether
   MacroFactor / Cronometer / MyFitnessPal actually write readable
   `dietaryProtein` is unverified. If they mostly do not, the Sources screen
   degrades to a near-empty list and the import claim has to come off the
   product page before submission.
2. Keyword volume is the binding constraint, not the build (`aso-plan.md`).
3. PROTEIN PAL is a registered mark. Only a Justia search was run, never a real
   USPTO clearance.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
