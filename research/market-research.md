# Caffeine Clearance / Caffeine Curfew

Research dossier, updated 2026-08-01.

## Recommendation

Caffeine is a real Apple Watch complication niche, but it is not an empty market. The best product is not “daily caffeine total.” It is:

> “How much caffeine is still active, and when will I be clear enough for sleep?”

The metric is dynamic, glanceable, and naturally suited to a complication. However, several current products already deliver the core behavior, so this is a smaller experiment or a later portfolio app rather than the next build after Protein Remaining and Recovery Countdown.

## Specific niche

### Primary user

- Daily coffee drinkers who care about sleep.
- People experimenting with a caffeine cutoff.
- Shift workers and people with late schedules.
- Athletes who use caffeine around training but want a sleep-aware cutoff.
- Apple Watch users who want to log a drink without opening a phone app.

### Core outputs

```text
Active caffeine: 142 mg
Clear by: 11:20 PM
Bedtime residual: 38 mg
```

The amount consumed today is secondary. The unique value is the estimated active amount after time-based decay.

## Why a complication is useful

Unlike Sleep Score, caffeine is changing throughout the day. A cup at 8:00 AM and a cup at 4:00 PM should produce different answers at 8:00 PM. A user may look before:

- ordering another coffee;
- starting a late workout;
- going to bed;
- deciding whether the current dose is already enough.

This is a stronger complication candidate than a static daily total.

Apple’s own ClockKit sample includes a caffeine-dose complication showing the estimated amount remaining in the body. Apple also publishes a Coffee Tracker example that uses HealthKit caffeine samples and a complication timeline. [Apple caffeine complication sample](https://developer.apple.com/documentation/clockkit/providing-multiple-complications), [Apple Coffee Tracker timeline](https://developer.apple.com/documentation/clockkit/creating-and-updating-a-complication-s-timeline)

## HealthKit data

Apple exposes `HKQuantityTypeIdentifier.dietaryCaffeine`, a Nutrition type measured as a quantity. [Apple Nutrition identifiers](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers?changes=_6), [Apple dietary caffeine type](https://developer.apple.com/documentation/HealthKit/HKQuantityTypeIdentifier/dietaryCaffeine?language=objc)

The data flow can be:

```text
Drink logger -> Apple Health dietaryCaffeine -> our decay model -> App Group cache -> complication
```

As with protein, the source app must actually write usable caffeine samples. HealthKit is the bridge, not a guarantee that every coffee or food app shares its data.

The most dependable launch behavior is:

- read HealthKit caffeine samples when available;
- offer our own quick-add input on the Watch;
- store own drink metadata locally, including the drink name and estimated milligrams;
- optionally write own caffeine samples back to HealthKit;
- use source selection and duplicate handling if external and local data overlap.

## Model

### Basic decay

For each logged dose:

```text
activeDose(t) = doseMg * 0.5 ^ ((t - consumedAt) / halfLifeHours)
activeCaffeine(t) = sum(activeDose(t))
```

This gives a simple, explainable curve. The app can calculate:

- current active caffeine;
- projected active caffeine at bedtime;
- time when active caffeine falls below the user’s chosen threshold;
- daily consumed total;
- number of doses still affecting the estimate.

The model should use a default half-life but allow the user to adjust it. The exact number varies across people and circumstances. Never present the calculated clear time as a physiological measurement.

### Optional absorption model

A later version can model a short absorption delay, but that is not necessary for the first product. A simple immediate-dose curve is easier to understand and makes the initial behavior predictable.

### User settings

- Desired bedtime.
- Caffeine threshold at bedtime.
- Half-life preset: faster, typical, slower.
- Custom half-life for advanced users.
- Default drink sizes.
- Preferred units: mg or cups.

Avoid pretending that user weight alone can make the estimate exact. Use adjustable assumptions and explain the result.

## Competitor map

| Competitor | Current positioning | Watch/complication evidence | Opportunity |
|---|---|---|---|
| Caffeine App | Caffeine and water tracker | Apple Watch app, quick logging, optimal sleep time complication, Health integration, about 340 ratings and 4.6 in the US listing | Strong incumbent; opportunity is simpler focus and better reliability |
| HiCoffee | Coffee database and caffeine tracker | Apple Watch, widgets, Health sync, Shortcuts, 2,500 branded coffee products, about 103 ratings and 4.7 in the Canada listing | Strong Apple ecosystem polish; database is a differentiator we should not copy initially |
| Caffeine Curfew | Active caffeine decay and sleep protection | Apple Watch app, active mg, half-life customization, HealthKit, widgets, about 14 ratings and 4.6 in the US listing | Newer direct competitor; validates the niche but lowers whitespace |
| CoffeeWatch | Current caffeine, metabolism curve, bedtime residual | Watch logging and complications for current in-body caffeine, curve, and bedtime residual; not enough ratings to show an overview | Directly overlaps the ideal feature set |
| Apple Coffee Tracker sample | Developer sample | Official complication timeline example | Confirms the technical shape, not a consumer competitor |

Sources: [Caffeine App](https://apps.apple.com/us/app/caffeine-app-daily-tracker/id1045959983), [HiCoffee](https://apps.apple.com/ca/app/hicoffee-caffeine-tracker/id1507361706), [Caffeine Curfew](https://apps.apple.com/us/app/caffeine-curfew-sleep-coach/id6757022559), [CoffeeWatch](https://apps.apple.com/ca/app/coffeewatch-caffeine-tracker/id6748468232)

### Community signals

- Users have asked for an Apple Watch complication that shows expected caffeine at bedtime and stays current from Apple Health. [Apple Watch caffeine discussion](https://www.reddit.com/r/AppleWatch/comments/11fkb6h/caffeine-metabolism-tracker/)
- HiCoffee is already used as a face complication showing current caffeine, daily total, and remaining caffeine at bedtime. [HiCoffee complication discussion](https://www.reddit.com/r/applewatchfaces/comments/1ryzz6y/stats-and-graphs/)
- New developers continue to launch Watch-native caffeine trackers, including apps focused on active caffeine and sleep protection. [Caffeine tracker launch](https://www.reddit.com/r/AppleWatchApps/comments/1u0p6rm/i_built_an_app_that_tells_you_exactly_when_to/)

The market signal is positive, but the category is already competitive. We would need a sharper angle than “another caffeine tracker.”

## Possible differentiation

### Option A: Caffeine for sleep

Make the product answer only:

```text
Can I have another coffee and still be below my bedtime threshold?
```

This is the clearest consumer promise.

### Option B: Caffeine for athletes

Add workout timing:

- caffeine taken before training;
- active caffeine at workout time;
- post-workout sleep protection;
- training-day versus rest-day patterns.

This targets fitness users but requires careful claims and creates more complexity.

### Option C: The fastest private logger

Compete on:

- one-tap Watch log;
- no account;
- no AI coach;
- no cloud;
- no database required for custom drinks;
- direct HealthKit write/read;
- a clear, reliable complication.

This fits the existing local-first portfolio best.

## Complication design

| Family | Primary display |
|---|---|
| Circular | Active mg with threshold ring |
| Rectangular | `142mg active` and `Clear 11:20 PM` |
| Inline | `Caffeine 142mg · clear 11:20` |
| Corner | `142` or a compact status color |

Quick-add actions should live in the Watch app, widget, App Intent, or Siri. The complication itself should open the app rather than attempt an unsafe tap-to-write shortcut.

### Timeline strategy

Because caffeine decays continuously, create timeline entries at meaningful intervals, such as every 30 or 60 minutes, and reload after a new dose. The system can delay updates, so the Watch app should calculate the current value locally from the last cached dose when opened.

Use a visible `last logged` timestamp in the iPhone app and a stale state if the source data has not refreshed.

## Reusable local infrastructure

### Vitals / Total Calories

Vitals already has a dietary HealthKit flow for `dietaryEnergyConsumed`:

- separate dietary permission request;
- daily cumulative query;
- background delivery;
- daily cache;
- WidgetKit reload;
- Watch complication reading shared SwiftData.

The caffeine app can port that structure and replace the quantity type with `dietaryCaffeine`. See [Vitals HealthKitService](../vitals/Shared/Services/HealthKitService.swift) and [Vitals Watch complication](../vitals/VitalsWatchWidget/WatchComplication.swift).

### VO2

VO2 provides defensive authorization and a simple App Group-backed analysis/cache pattern. It is useful as a template, not a product dependency.

### Headache Logger archive

Headache Logger provides one-tap Watch input, WatchConnectivity queueing, App Intents, and local persistence. These are directly applicable to a quick “log coffee” interaction.

## MVP

### Free

- Set bedtime.
- Add custom drinks and milligrams.
- Watch quick log.
- Current active caffeine.
- Clear-time estimate.
- One complication.
- Local persistence.
- Optional HealthKit read.

### Premium

- Multiple sleep thresholds.
- Drink library and branded products.
- Trends by drink and time.
- Sleep correlation view.
- More complication variants.
- Shortcuts and advanced reminders.

### Do not build first

- AI sleep coach.
- Huge coffee database.
- Water tracking, unless it is intentionally a bundle.
- Medical or psychiatric claims.
- “Exact” metabolism language.

## Main risks

1. **Existing competitors already have the core feature.** The market is validated but not empty.
2. **Manual logging friction.** If users forget to log the drink, the model is wrong. Watch input is essential.
3. **Half-life uncertainty.** Use assumptions and confidence language.
4. **HealthKit source gaps.** External food apps may write caffeine inconsistently.
5. **Small audience.** Caffeine awareness is common, but paying for a dedicated tracker is a narrower behavior than tracking calories.

## Decision

Keep this as a viable small app or a fast portfolio experiment. It is technically easier than Recovery Countdown and has a better dynamic complication story than Sleep Score. It should not displace Protein Remaining or Recovery Countdown unless a quick competitor test shows unusually strong demand for our simpler private implementation.

## Sources

- [Apple Nutrition identifiers](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers?changes=_6)
- [Apple dietary caffeine](https://developer.apple.com/documentation/HealthKit/HKQuantityTypeIdentifier/dietaryCaffeine?language=objc)
- [Apple caffeine dose complication sample](https://developer.apple.com/documentation/clockkit/providing-multiple-complications)
- [Apple Coffee Tracker timeline sample](https://developer.apple.com/documentation/clockkit/creating-and-updating-a-complication-s-timeline)
- [Caffeine App](https://apps.apple.com/us/app/caffeine-app-daily-tracker/id1045959983)
- [HiCoffee](https://apps.apple.com/ca/app/hicoffee-caffeine-tracker/id1507361706)
- [Caffeine Curfew](https://apps.apple.com/us/app/caffeine-curfew-sleep-coach/id6757022559)
- [CoffeeWatch](https://apps.apple.com/ca/app/coffeewatch-caffeine-tracker/id6748468232)
- [Apple Watch caffeine discussion](https://www.reddit.com/r/AppleWatch/comments/11fkb6h/caffeine-metabolism-tracker/)
- [HiCoffee complication discussion](https://www.reddit.com/r/applewatchfaces/comments/1ryzz6y/stats-and-graphs/)
- [New Apple Watch caffeine tracker](https://www.reddit.com/r/AppleWatchApps/comments/1u0p6rm/i_built_an_app_that_tells_you_exactly_when_to/)
