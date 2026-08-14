# Protein Remaining

Research dossier, updated 2026-08-01. **Partly superseded 2026-08-04** — read the docs below first.

**The app is built.** `CLAUDE.md` is the project guide and the current source of
truth for architecture and decisions; this file is kept as the HealthKit dossier
and the record of how the direction was reached.

| Doc | What it holds |
|---|---|
| `CLAUDE.md` | **The built app.** Architecture, free/Protein+ split, gotchas, open risks. |
| `docs/positioning.md` | **The locked direction.** Start here. |
| `docs/plan.md` | **The build plan.** Targets, port map, phases, open risks. |
| `aso-plan.md` | Measured keyword reality. The protein category is a one-keyword category. |
| `docs/scoping.md` | What reuses from Vitals, what is genuinely new, what v1 costs |
| `research/competitors.md` | 15 protein-only competitors, watch-gap audit, pricing, audience evidence |
| This file | HealthKit dossier and implementation shape — still the reference for `dietaryProtein` work |

**Corrections to this file as of 2026-08-04:**

- The competitor map understates MacroFactor. It shipped a real Watch app (v5.4.0, 2025-09-09) and per its own site ships protein/carb/fiber complications plus wrist voice logging. "First to put protein on the wrist" is no longer available as a claim.
- The watch-first thesis below is sound as a **product** bet but is not an **ASO** bet: every Watch keyword measures at the popularity floor. See `aso-plan.md`.
- The go/no-go test below (do two mainstream apps write `dietaryProtein`) is still worth running but is not the binding constraint. The binding constraint is keyword volume.

## Recommendation

Build a watch-first **Protein Remaining** app for people who already care about protein targets, especially strength trainees, lifters, high-protein dieters, and active adults trying to gain or preserve muscle.

The product should not try to replace MyFitnessPal, Cronometer, MacroFactor, or a full food database. The sharper product is:

> “See how much protein you have eaten, how much remains, and add a repeat food from your wrist.”

The strongest wedge is a reliable complication and fast input surface. The food database and AI meal logging can remain optional or be delegated to an existing logger through Apple Health.

## Build identity

- Bundle ID: `com.jackwallner.protein`
- App Store Connect record: `Protein App Placeholder` (`6797089333`)
- RevenueCat public iOS SDK key: stored locally in `~/.protein_credentials`
- RevenueCat connectivity was verified against the offerings endpoint on 2026-08-01.

The `appl_` key is for device, Release, TestFlight, and App Store builds. Future simulator runs must skip `Purchases.configure` with this production key and use local Pro or StoreKit configuration instead.

## Direct answer to the HealthKit question

Yes, the app can read protein entered by another app if that app writes protein samples into Apple Health.

The HealthKit type is `HKQuantityType(.dietaryProtein)`. Apple defines it as a cumulative quantity measured in mass units, so a daily total can be calculated by summing the day’s samples in grams. The user must grant read permission, and the source app must have written the data. HealthKit does not give us a private MyFitnessPal account feed or a guarantee that every app writes every nutrient.

The safe integration statement is:

> “Import protein from Apple Health when your food logger shares it.”

Do not promise “automatic MyFitnessPal protein sync” until it is verified on a real device with current versions of the apps.

Our own input is straightforward and should be part of the first version. The Watch should offer saved foods, saved meals, and gram quick-add buttons. The iPhone can provide search, barcode, custom foods, and editing.

## Specific niche

### Primary user

An Apple Watch owner who:

- lifts, does resistance training, bodybuilding, CrossFit, running, or mixed training;
- has a daily protein target, often roughly expressed as grams per day;
- already logs food in a larger app, or is willing to use a very small protein-only logger;
- wants to know the answer at the moment they are deciding what to eat;
- does not want a full calorie diary on the Watch.

### Jobs to be done

1. “How much protein have I had today?”
2. “How much do I need to hit my target?”
3. “Can I add my usual shake or chicken meal in one tap?”
4. “Did my other food app actually update the Watch complication?”
5. “Can I see the number without opening a calorie-counting app?”

### Positioning

The product is not a macro coach, meal planner, calorie counter, or AI nutrition adviser. It is a **protein target and wrist logging utility**.

That distinction matters. The large apps compete on databases, recipes, coaching, and photo recognition. We can compete on the one metric that users want in a glanceable, reliable form.

## Demand evidence

### User requests and pain

- Apple Watch users have asked for a calorie and protein remaining complication, plus the ability to add protein from the Watch. The request is specifically about reducing the friction of opening a phone food logger. [Apple Watch Fitness request](https://www.reddit.com/r/AppleWatchFitness/comments/1kb11r1/help_is_there_a_calorie_tracking_app_that_lets_me_add_protein/)
- MacroFactor users have requested a complication that shows calories and protein remaining. [MacroFactor complication request](https://www.reddit.com/r/MacroFactor/comments/15647xw/apple_watch_complication/)
- Cronometer users have complained that the daily macro progress display shows consumed and percentage values but not the amount of protein, carbohydrate, and fat remaining. [Cronometer App Store review](https://apps.apple.com/us/app/cronometer-calorie-counter/id1145935738?uo=4)
- MyNetDiary users have reported that the app has the correct protein data but its complications do not update reliably. [MyNetDiary complication complaint](https://www.reddit.com/r/mynetdiary/comments/1t3i5jb/apple_watch_complications_dont_update/)
- MyFitnessPal users have reported stale protein values on their Watch complications even when the app itself is current. [MyFitnessPal complication complaint](https://www.reddit.com/r/applewatchultra/comments/1r85loy/awu3_only-shows-65-protein-with-myfitnesspal/)

The repeated need is not only “show protein.” It is “show protein remaining and keep the number fresh.” Reliability is therefore part of the product opportunity.

### App Store validation

Ratings are directional evidence of demand, not a revenue estimate, and counts vary by storefront.

- [Protein Pal](https://apps.apple.com/us/app/protein-tracker-protein-pal/id1541193285) is a focused protein tracker with thousands of ratings in the US listing, a strong rating, daily targets, quick additions, history, and statistics. It is iPhone-only. This validates the simple protein-only behavior while leaving the Watch surface open.
- [Cronometer](https://apps.apple.com/us/app/cronometer-calorie-counter/id1145935738) has roughly 90K ratings in the US storefront, supports protein and broader nutrition, and supports Apple Watch and Apple Health. It is a powerful general tracker, not a focused single-metric complication product.
- [MacroFactor](https://apps.apple.com/us/app/macrofactor-macro-tracker/id1553503471) has roughly 18K ratings, a strong rating, and added Apple Watch support in 2025. It is a premium full macro coach with a database, coaching algorithm, and food log.
- [ProteinLog](https://apps.apple.com/us/app/proteinlog-macro-tracker/id6759217872) is a newer Apple Watch and Apple Health competitor with AI photo, voice, text, barcode, saved meals, and macro logging. It has broad scope and requires an active subscription. The listing does not show enough ratings to demonstrate an entrenched category leader.
- [Protein Pal](https://apps.apple.com/gb/app/protein-tracker-protein-pal/id1541193285) remains iPhone-only in the UK listing and emphasizes the simple target, add, history, and statistics loop.

The competitive pattern is favorable for a narrow utility. Full food trackers exist, but users still ask for the one number and the one complication they cannot get reliably.

## Competitor map

| Competitor | Position | Apple Watch | Apple Health | Protein-focused | Opportunity against it |
|---|---|---:|---:|---:|---|
| MyFitnessPal | General calorie and food logger | Yes, but complication freshness is a reported pain point | Official HealthKit integration | No | Read its HealthKit output when available, then offer a simpler number |
| Cronometer | Detailed macro and micronutrient tracker | Yes, including food logging | Yes | No | Make protein remaining the hero instead of 95+ nutrients |
| MacroFactor | Premium macro coach and expenditure model | Yes since 2025 | Yes, with ongoing nutrition integration | No | Be cheaper, simpler, and complication-first |
| Lose It! | Calorie and weight-loss tracker | Yes | Yes | No | Avoid full diet planning; use Apple Health as a bridge where samples exist |
| MyNetDiary | Diet tracker with Watch data | Yes | Yes | No | Compete on data freshness and one metric |
| Bevel | Broad health, recovery, sleep, strength, and nutrition coach | Yes | Yes | No | Avoid being a dashboard among many scores |
| Protein Pal | Simple protein tracker | No, iPhone-only | Verify current release behavior | Yes | Add the wrist surface and better daily glanceability |
| ProteinLog | AI meal logging and full macro tracker | Yes | Yes | Yes, but broad | Do not compete on AI; focus on repeat logging and reliable complications |

## Can we pull from MyFitnessPal or another app?

### Apple Health is the bridge, not a direct partner API

Apple Health records the source app for each sample. A query can inspect the sample source, so the app can answer questions such as “which apps are currently writing dietary protein?” Apple documents source queries and sample queries for this purpose. [Reading data from HealthKit](https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit), [sample source](https://developer.apple.com/documentation/healthkit/hksourcerevision/source)

The data flow is:

```text
Food logger -> Apple Health dietaryProtein samples -> Protein Remaining -> cache -> Watch complication
```

There is no need to authenticate with MyFitnessPal if its samples are already in Apple Health. Conversely, there is no supported way for our app to retrieve a user’s private MyFitnessPal cloud diary directly through HealthKit.

### Source compatibility matrix

| Source | What its current documentation confirms | Protein import confidence | Build decision |
|---|---|---:|---|
| MyFitnessPal | Its official Apple Health help says it sends food meal summaries containing calories and some nutrients to Apple Health. It does not enumerate dietary protein in the current article. It also says food does not flow from Apple Health back into MyFitnessPal. [MFP HealthKit help](https://support.myfitnesspal.com/hc/en-us/articles/360032271092-Apple-Health-FAQ-and-Troubleshooting) | Medium, must verify on device | Support as a detected HealthKit source, but do not market guaranteed MFP protein until tested |
| Cronometer | Official support confirms Apple Health integration. Its App Store listing confirms protein tracking, Apple Health, and Apple Watch. [Cronometer integrations](https://support.cronometer.com/hc/en-us/articles/360024748771-Mobile-Integrations), [App Store](https://apps.apple.com/us/app/cronometer-calorie-counter/id1145935738) | Medium-high, exact sample identifiers not publicly enumerated | First external source to test |
| MacroFactor | Official help says it exports nutrition information to Apple Health, supports ongoing sync, and lets users select integrations by data type. [MacroFactor Apple Health help](https://help.macrofactorapp.com/en/articles/65-connect-health-connect-or-apple-health), [integrations](https://help.macrofactorapp.com/en/articles/102-integrations) | High for nutrition, exact protein sample still needs device verification | First external source to test alongside Cronometer |
| Lose It! | Official support says it sends food to Apple Health and supports nutrient goals such as protein, fat, and carbs for Premium users. It does not clearly promise consumed protein quantity samples in the current article. [Lose It! Apple Health help](https://loseit.zendesk.com/hc/en-us/articles/47773580085140-Using-Apple-Health-With-Lose-It) | Medium-low | Treat as optional; do not make it a launch dependency |
| ProteinLog | App Store listing claims Apple Health and Apple Watch integration. [ProteinLog](https://apps.apple.com/us/app/proteinlog-macro-tracker/id6759217872) | Unknown | Test if installed, but do not depend on a new competitor |

### Real-device verification plan

For each source app:

1. Create a fresh test HealthKit profile.
2. Give the source app permission to write Nutrition data.
3. Log a meal with a distinctive protein amount, such as 37 g.
4. In Apple Health, inspect Nutrition > Protein and the source list.
5. Confirm whether the source writes `dietaryProtein`, a food correlation, only calories, or nothing.
6. Install our test reader and query both quantity samples and their `HKSourceRevision`.
7. Log a second meal and confirm an observer/background delivery causes a refresh.
8. Turn off the source’s write permission, delete a sample, and verify our cache does not preserve a false total.
9. Repeat with two sources enabled to detect double counting.

The result should be stored as a compatibility table in the app repo, not assumed from marketing copy.

## Own input design

Own input is not just a fallback. It is the reliability moat.

### Watch input

The Watch should be optimized for repeat consumption, not full food search:

- Saved foods: whey shake, Greek yogurt, eggs, chicken, protein bar.
- Saved meals: breakfast, post-workout shake, lunch, dinner.
- Quick gram buttons: 10 g, 20 g, 25 g, 30 g, 40 g.
- Custom “add grams” picker.
- Undo last entry.
- Optional “log meal” with a compact label.
- Siri/App Intent: “Log 30 grams of protein.”

The interaction should take less than ten seconds for a repeat item.

### iPhone input

- Target grams per day.
- Saved food and meal editor.
- Food search and barcode scanning only if we decide to own a database.
- Import source selection.
- History and correction tools.
- Separate display of imported and locally logged data during testing.

### HealthKit writing policy

The simplest launch is read-only import plus our own local log. A later version can optionally write our own entries to HealthKit. If we write to HealthKit and then read all protein samples back, we must avoid counting our own samples twice.

Recommended policy:

- Keep a local entry UUID and source marker.
- Treat local entries as the canonical product data.
- If the user enables HealthKit writing, write samples with our app as source.
- When importing, identify our own source and either exclude it from external totals or reconcile it explicitly.
- Let the user choose one external food source, rather than summing every source by default.

HealthKit is designed to merge data from multiple sources, but the product still needs a nutrition-specific priority rule. Two food loggers can both write the same meal, which makes a naive cumulative sum wrong. [HealthKit overview](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework), [saving data](https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit)

## HealthKit implementation shape

### Types and queries

```swift
let proteinType = HKQuantityType(.dietaryProtein)
let grams = HKUnit.gram()
```

For a daily total:

- Use a day predicate.
- Use a cumulative statistics query with `HKQuantityAggregationStyle.cumulativeSum`.
- Convert the result to grams.
- For source diagnostics, use sample queries and inspect `sourceRevision.source.name`.
- Store individual sample UUIDs when a sample-level cache is needed.

For automatic refresh:

- Install an `HKObserverQuery` for dietary protein.
- Enable background delivery at an hourly frequency where permitted.
- Re-query after the observer fires because the observer only tells us that something changed.
- Debounce multiple deliveries.
- Save the daily result to SwiftData in the App Group container.
- Call `WidgetCenter.shared.reloadAllTimelines()` after the cache updates.

Apple documents observer queries as long-running queries that wake the app when matching samples are saved or deleted. The callback does not include the changed samples, so a follow-up query is required. [HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery), [executing observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)

### Duplicate handling

Do not use one unrestricted sum across every source without testing. The cache should retain:

- source name and bundle identifier;
- sample UUID;
- start and end date;
- grams;
- whether the sample was imported or written by us;
- last observed date;
- user-selected inclusion state.

The default product setting can be:

```text
Our entries + one selected external source
```

An advanced screen can show “other sources detected” and warn about possible duplicates.

## Watch complication design

**Superseded 2026-08-13.** The recommendation below (remaining grams as the
primary value) was reversed: every surface now leads with grams tracked,
counting up, with the target as the caption. See `CLAUDE.md`.

### Recommended complication variants

| Family | Display |
|---|---|
| Circular | Progress ring, `124g` or `78%` |
| Rectangular | `124 / 160 g` and `36 g left` |
| Inline | `Protein 124g · 36g left` |
| Corner | `124g` or a compact progress value |

The most useful primary value is probably **remaining grams**, not consumed grams:

```text
36g left
```

Consumed grams are better as a secondary option because they answer “what have I done?” while remaining grams answers “what should I do next?”

### State handling

- No target: `Set goal`.
- No samples: `0g · Add protein`.
- Imported data old: show the value with a stale timestamp in the app, not silently as current.
- External source unavailable: keep the last known value but label it stale in the app.
- Day rollover: reset local display at midnight, then allow late-arriving samples to backfill.
- Target exceeded: `+18g over`, not a negative remaining value.

### Update expectations

Complications are timeline-based and the system can delay updates. An observer-triggered reload improves freshness but does not provide a hard real-time guarantee. This is why the product should not claim “instant” external sync. The practical reliability target is:

- local Watch quick-add updates immediately through the shared cache or WatchConnectivity;
- HealthKit imports refresh when the source writes and the system delivers the observer;
- foreground app refresh always reconciles from HealthKit;
- the complication provides hourly fallback timeline entries.

## Reusable local infrastructure

### Strongest source: Vitals / Total Calories

The production Vitals app already has almost the exact skeleton:

- `HKQuantityType(.dietaryEnergyConsumed)` is already requested separately;
- `fetchDietaryEnergyToday()` and `fetchDietaryHistory()` already use daily cumulative HealthKit queries;
- dietary background delivery is already installed conditionally;
- cache writes update the current daily row;
- the Watch complication reads from shared SwiftData rather than querying HealthKit directly;
- the App Group and RevenueCat patterns are already in place.

The likely port is to replace the food-calorie quantity with `dietaryProtein`, add protein-specific models and goals, and add own-input records. See [Vitals HealthKitService](../vitals/Shared/Services/HealthKitService.swift), [Vitals cache model](../vitals/Shared/Models/HealthRecord.swift), [Vitals Watch complication](../vitals/VitalsWatchWidget/WatchComplication.swift), and [Vitals project guide](../vitals/CLAUDE.md).

### VO2

VO2 has a more defensive HealthKit authorization state machine, App Group cache, WidgetKit complication target, pure analysis utilities, and a test-heavy Swift 6 setup. See [VO2 HealthKitService](../health/Shared/Services/HealthKitService.swift), [VO2 DataService](../health/Shared/Services/DataService.swift), and [VO2 Watch complication](../health/VO2MaxWatchWidget/WatchComplication.swift).

### Headache Logger archive

The archived Headache Logger has useful patterns for:

- broad HealthKit read authorization;
- an actor-based HealthKit service;
- WatchConnectivity queueing;
- one-tap Watch input;
- App Intent/widget logging;
- local-only persistence.

See [archived HealthKitService](../vitals/_archive/headaches-retired-2026-04-14/HeadacheLogger/Services/HealthKitService.swift) and [WatchConnectivity controller](../vitals/_archive/headaches-retired-2026-04-14/HeadacheLoggerWatch/WatchConnectivityController.swift).

### Product fleet

Reuse the Vitals/VO2 conventions for:

- XcodeGen and separate iPhone, Watch, widget, and test targets;
- local SwiftData in an App Group;
- RevenueCat freemium and local Pro entitlement mirroring;
- privacy manifest and HealthKit usage descriptions;
- headless simulator and TestFlight scripts;
- the existing Total Calories visual language where useful.

## Proposed MVP

### Free

- Set a protein target.
- Read `dietaryProtein` from Apple Health.
- Select one external source.
- Add saved foods and meals locally.
- Watch app with today’s consumed and remaining values.
- Four Watch complication families.
- iPhone history: 7 days free, everything logged with Protein+.
- On-device storage, no account.

### Premium

- Unlimited saved foods and meals.
- Protein pacing by time of day.
- Meal distribution history.
- Weekly adherence and streaks.
- Multiple external-source diagnostics.
- Advanced widgets and reports.

### Do not build first

- AI photo estimates.
- Full food database.
- Calorie coaching.
- Medical nutrition advice.
- Social feed.
- Cloud account system.

## Main risks

1. **External apps do not all write protein consistently.** Make our own logging complete enough to stand alone.
2. **Duplicate samples.** Source selection and sample-level reconciliation are required.
3. **Complication freshness.** HealthKit and WidgetKit update budgets are outside our control, so provide local quick-add and a visible last-updated state.
4. **Food logging friction.** The app wins only if repeat entries are materially faster than opening a full tracker.
5. **Nutrition claims.** Frame targets as user-set tracking goals, not universal medical or dietary prescriptions.

## Go / no-go test

Go if a real-device test confirms that at least two mainstream apps, ideally MacroFactor and Cronometer, write usable `dietaryProtein` samples to HealthKit, and our local quick-add flow is faster than opening either app.

Do not make MFP the dependency. Its current help page confirms food and some nutrient sharing, but not a guaranteed protein sample contract.

## Sources

- [Apple dietaryProtein type](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietaryprotein?changes=_6__8)
- [Apple nutrition identifiers](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers?changes=_6)
- [Apple reading HealthKit data](https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit)
- [Apple source query documentation](https://developer.apple.com/documentation/healthkit/hksourcerevision/source)
- [Apple observer queries](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- [Apple background observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- [MyFitnessPal Apple Health FAQ](https://support.myfitnesspal.com/hc/en-us/articles/360032271092-Apple-Health-FAQ-and-Troubleshooting)
- [Cronometer mobile integrations](https://support.cronometer.com/hc/en-us/articles/360024748771-Mobile-Integrations)
- [MacroFactor Apple Health integration](https://help.macrofactorapp.com/en/articles/65-connect-health-connect-or-apple-health)
- [MacroFactor integrations](https://help.macrofactorapp.com/en/articles/102-integrations)
- [Lose It! Apple Health support](https://loseit.zendesk.com/hc/en-us/articles/47773580085140-Using-Apple-Health-With-Lose-It)
- [Protein Pal](https://apps.apple.com/us/app/protein-tracker-protein-pal/id1541193285)
- [Cronometer](https://apps.apple.com/us/app/cronometer-calorie-counter/id1145935738)
- [MacroFactor](https://apps.apple.com/us/app/macrofactor-macro-tracker/id1553503471)
- [ProteinLog](https://apps.apple.com/us/app/proteinlog-macro-tracker/id6759217872)
- [MacroFactor complication request](https://www.reddit.com/r/MacroFactor/comments/15647xw/apple_watch_complication/)
- [MyNetDiary complication report](https://www.reddit.com/r/mynetdiary/comments/1t3i5jb/apple_watch_complications_dont_update/)
- [MyFitnessPal stale protein report](https://www.reddit.com/r/applewatchultra/comments/1r85loy/awu3_only_shows_65_protein_with_myfitnesspal/)
