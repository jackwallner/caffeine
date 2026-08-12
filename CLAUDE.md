# Protein Tracker — Project Guide

Pure protein tracking: one gram target, one number, wrist-first. XcodeGen
project/scheme: `Protein`, sim lease owner `protein` (`protein-watch` for a
paired-watch lease).

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency)
- HealthKit (`dietaryProtein`, read **and** write), SwiftData in an App Group,
  WidgetKit, WatchConnectivity
- XcodeGen (`project.yml`). Targets: iOS 17+, watchOS 10+
- RevenueCat, entitlement lookup key `Protein+` (same string as the branding)

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
  (target, presets, entitlement, excluded sources), phone → watch, via
  `applicationContext`. Exclusions belong on that list: HealthKit hands both
  devices the same samples, so a wrist that has not been told a source was
  switched off keeps summing it and disagrees with the phone all day.
- **Double counting is not a special case.** One sum over one source set.
- **Write auth can be denied**, and HealthKit says so honestly. `ProteinLogService`
  falls back to `LocalProteinEntry` rows, which are summed alongside the
  HealthKit samples and migrated in later by `retryPendingLocalEntries()`. This
  path ships in v1; do not let it rot. **Both devices run it**: the watch has its
  own App Group, so grams stranded there can only be rescued by the watch itself.
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
- `Shared/Utilities/ProteinInsights.swift` — streaks, days on target, month-on-month
- `Shared/Services/TargetHistoryService.swift` — what a target change does to past days

## Free vs Protein+

**Logging is free, everywhere** (decided 2026-08-10). Adding grams on the phone
and on the wrist, the three quick-add buttons, and any amount you like: all
free, along with the target, today's total imported from Apple Health, source
controls, the widget, the complication, and 7 days of history. An app whose
whole job is "tap a number" cannot charge before the first tap.

Protein+ is what a month of that adds up to: **every day you have logged**
(changed 2026-08-12 from a 30-day cap), streaks and month-on-month trends (the
Protein+ tab), setting the three quick-add buttons to your own amounts, and the
evening reminder. `PlusFeature` in `PaywallView.swift` is the single source of
truth for the list; every pitch surface reads it.

History is unbounded because HealthKit already stores it: `fetchFullHistory()`
queries ten years and trims the leading empty days, so the range starts when the
user did. The History screen offers 7 / 30 / 90 / All, and past 90 loaded days
the chart switches to a bar per week (`ProteinInsightsBuilder.weeks`) with
*averages*, because a weekly sum against a daily target line compares two
different units. The Protein+ tab still compares this month with the last one;
only Best streak reads the whole history.

The three quick-add buttons ship at 25/30/40 g and work for everyone. A lapsed
subscriber keeps whatever amounts they set — locking the editor is the gate, and
reverting their buttons would be a punishment for cancelling.

The complication keeps updating for free users on purpose. It costs nothing and
it is what keeps the app on the wrist while they reconsider; the graveyard
clones in `aso-plan.md` collect one-star reviews for taking everything away.

**Tabs are Today, History, Protein+, Settings.** The Protein+ tab is an embedded
paywall for free users (`impressionID: "protein_plus_tab"`) and the subscriber
hub otherwise, the same shape as VO2+ and Vitals+. Off-screen it renders
`Color.clear` so a paywall nobody opened logs no impression and puts nothing in
front of VoiceOver.

**Changing the target asks about the past.** History rows print the target that
was in force on the day, but a day the app never reconciled has no row and falls
back to the current target — so doing nothing is not neutral, and raising the
target silently turns a week of green days red. `TargetHistoryService` makes
both answers a write.

It stores a **change log** ("from this day forward, the target was N") in the
App Group defaults, not a row per day. Keeping the past appends one entry;
applying it collapses the log to a single all-time entry and rewrites the stored
rows. This replaced a 60-day window that materialized a `DailyProteinRecord` per
past day (2026-08-12): once history went unbounded, that meant inserting a row
for every day since install on every target change, and any day older than the
window silently inherited the new target. Stored rows still outrank the log —
they are what the day was actually reconciled against.

Access model: **one StoreKit trial**, decided 2026-08-04. The offer sheet is the
final onboarding step and StoreKit owns the 7 days. There is no separate local
trial window — `docs/plan.md` §7 flagged the stacked alternative and it was
rejected.

## App-specific notes
- **Review funnel trigger**: the third distinct day the user hits their target
  (`ReviewPromptTracker.recordTargetHit`), never before. App Store ID 6797089333.
- **App Review 1.4.1**: the lifter / GLP-1 / post-bariatric stories stay "track
  the target you were given". Never "we set your medical target". Two unit tests
  (`testReasonCopyMakesNoMedicalClaims`, `testCombinedRationaleMakesNoMedicalClaims`)
  fail the build on treat/cure/diagnose/prescribe/prevent appearing in the
  audience copy, the second across all 16 reason combinations — keep it that way.
- **Reasons are multi-select** (2026-08-10). They stack in real life: a lifter on
  a GLP-1 is one person with one target. Any medical reason in the set means the
  number is entered, never inferred; otherwise the most demanding reason sets the
  suggestion. Stored as `reasons` (array of raw values), migrated from the old
  single `reason` key on first launch.
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

## Release state (2026-08-11)

Build and tests are green (84 unit tests, all four targets). `scripts/asc-readiness.py`
reports the live state of everything below; run it rather than trusting this list.

**Done:** (`asc-readiness.py` run 2026-08-11: **no gaps**, all three URLs 200)

- TestFlight build 13 is uploaded, VALID, and **attached** to the 1.0 draft version.
  A draft version keeps the build that was attached first, so this needs
  re-pointing after every upload: build 8 stayed attached for two days after
  logging went free, which left the description promising a free tap that the
  attached binary charged for. `asc-readiness.py` fails when the attached build
  is not the newest VALID one, so the drift shows up before a submission, and
  **`scripts/asc-attach-build.py` fixes it** — it waits out processing and
  re-points the draft version. Run it after every `testflight.sh`.
- ASC products are all **READY_TO_SUBMIT**: `.monthly` $5.99, `.yearly` $29.99
  (both with a 1-week free trial in 175 territories and the Vitals PPP
  overrides), `.pro.lifetime` $59.99. Repriced up from $1.99 / $14.99 / $29.99
  effective 2026-08-10, the day logging went free: the old rows are preserved
  for anyone already subscribed. Nothing in the app hardcodes a price, but the
  App Store description, `docs/index.html`, `Protein.storekit`, and
  `StoreService.fixtureProducts()` all restate them, and all four were stale
  until 2026-08-11. Check them against ASC after any price change.
- The ASC record is renamed **Protein Tracker - Grams Left** (subtitle "Daily
  intake goal, on Watch"), genre Health & Fitness, with description, keywords,
  promo text, all three URLs, 4 iPhone 6.9" screenshots, App Store review notes,
  and the age-rating declaration (`healthOrWellnessTopics` true,
  `medicalOrTreatmentInformation` NONE — mirroring Total Calories).

- The repo is public at **github.com/jackwallner/protein** with Pages serving
  `main` `/docs`. The privacy, terms, and support URLs in the metadata all
  resolve 200.

**RevenueCat is wired (2026-08-05).** The `default` offering now returns all
three packages from the public SDK endpoint the app calls, so a device build
renders the paywall instead of "Protein+ Plans Unavailable".

The failure was never the App Store side. All three IAPs have been
READY_TO_SUBMIT throughout. The project had two apps, `Protein (App Store)` and
a `Test Store`, and every package was attached to a Test Store product with a
bare identifier (`monthly`, `yearly`, `lifetime`). There were **zero App Store
products** in the project. Asked with `X-Platform: ios`, RevenueCat filtered to
App Store products, found none in any package, and dropped all three, an empty
offering that looked like missing packages. The ASC API key being configured
does *not* import a catalogue; it resolves metadata for products you declare.

`scripts/rc-setup.py` created the three App Store products, attached them to the
`Protein+` entitlement, and attached each to its existing package. The Test
Store products stay attached alongside, which is what keeps paywall previews
working; iOS filters them out.

Two things worth knowing next time:

- **V2 secret keys are project-scoped.** Every other key on this machine (VO2
  Max, Bridge, Cribbage, Mahj, StatScout, Aging, Queasy, DreamCart) returns only
  its own project from `GET /v2/projects`. A new app needs a key minted in its
  own project: Dashboard → project → Project settings → API keys → **+ New** →
  Secret key, `project_configuration` read/write.
- The lifetime product lands as `non_renewing_subscription` rather than
  `non_consumable`, because that is what v2's `type: "one_time"` maps to. VO2
  Max and Bridge both look identical, so it is fleet-wide rather than a Protein
  bug, but it has never been confirmed against a real lifetime purchase.

The App Review notes were rewritten 2026-08-11 and amended 2026-08-12. They said
"PROTEIN+ ... unlocks logging" a day after the description started saying logging
is free, a contradiction sitting in the two documents a reviewer reads side by
side, and then said "thirty days of history" after history went unbounded. They
now lead with "logging is free, no reviewer action is needed to exercise the
core feature". Those notes live only in ASC, not in `fastlane/metadata`, so
nothing in the repo reminds you they went stale: re-read them after any change
to what is paid. There is no script; patch `/appStoreReviewDetails/{id}` with
`asc_lib` directly.

**Still blocking submission, needing Jack:**

1. **A real purchase has never been made on a device.** The offering resolves,
   which is necessary and not sufficient; sandbox-buy each of the three and
   confirm `Protein+` goes active.
2. **The Regulated Medical Device declaration**, which the API cannot reach.
   Answer **No** in the web UI — the app tracks a number the user or their
   clinician set and makes no diagnostic or treatment claim.
3. **Nobody has pressed Submit.** The 1.0 version is `PREPARE_FOR_SUBMISSION`
   and no `reviewSubmission` has ever been created. Everything else is staged;
   this is the last step, after 1 and 2.

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
