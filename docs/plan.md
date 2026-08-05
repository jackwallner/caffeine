# Protein Tracker - build plan

> Written 2026-08-04. Companion to `docs/positioning.md` (locked direction), `docs/scoping.md` (cost of the options), `aso-plan.md` (keyword reality), `research/competitors.md`, `README.md` (HealthKit dossier).
> This doc is the build. Nothing here reopens a positioning decision.

---

## 1. Locked decisions

| Decision | Answer | Where it came from |
|---|---|---|
| Positioning | Pure protein, no calories, explicitly anti-AI. Take the slot Protein Pal vacated. | `positioning.md` §1 |
| Form factor | Watch is the product. Phone is setup, sources, history. | `positioning.md` §1 |
| Scope | Ultra-simple. Read + reconcile + one number + gram quick-add. **No saved-foods library in v1.** | this doc §2 |
| Audience | Lifters, GLP-1, post-bariatric. One product, one onboarding fork. | `positioning.md` §2 |
| Name | `Protein Tracker - Grams Left` (28 chars) | 2026-08-04 |
| Price | $1.99/mo, $14.99/yr, $29.99 lifetime, 1wk StoreKit intro. Fleet baseline. | 2026-08-04 |
| Access model | Hard 7-day trial, then read-only. Complication survives expiry. | 2026-08-04 |
| HealthKit write | Yes. Our entries become real `dietaryProtein` samples. | 2026-08-04 |
| Import | Headline feature. Source picker + per-source freshness. Unverified against real loggers. | 2026-08-04 |
| Port base | App shell from `~/health` (VO2Max). Dietary read layer from `~/vitals` (Total Calories). | 2026-08-04 |

---

## 2. What v1 is, and what it is not

**In:**

- Onboarding fork (lifter / GLP-1 / post-bariatric) that sets a suggested target and nothing else
- Daily protein target, editable
- Grams-remaining ring on phone and wrist
- Watch complication (all accessory families)
- Watch quick-add: three tunable preset buttons plus a gram picker
- HealthKit import with a per-source picker and visible freshness
- Write-back to Apple Health as `dietaryProtein`
- 7-day history
- iPhone widget

**Out of v1** (each is a v1.1 candidate, none blocks launch):

- Saved-foods library, food names, meal editor
- App Intents / Siri
- WatchConnectivity (see §4, the architecture removes the need)
- Food database, barcode, AI anything
- Calories, carbs, fat
- Cloud sync, accounts

This is a deliberate cut from `scoping.md` §5, which selected the largest build shape. The Watch input surface stays, the saved-foods store and the WC write queue go. Those were the two Medium-Large items with no fleet precedent.

---

## 3. Targets and repo

`~/protein` is currently docs inside the local-only `~` repo. It becomes its own repo, nested the same way `~/vitals` and `~/health` already are.

Xcode project/scheme `Protein`, sim lease owner `protein`, bundle prefix already reserved by the ASC placeholder `6797089333` / `com.jackwallner.protein`.

| Target | Type | Bundle ID |
|---|---|---|
| `Protein` | iOS app | `com.jackwallner.protein` |
| `ProteinWidget` | iOS app-extension | `com.jackwallner.protein.widget` |
| `ProteinWatch` | watchOS app | `com.jackwallner.protein.watch` |
| `ProteinWatchWidget` | watchOS app-extension | `com.jackwallner.protein.watch.widget` |
| `ProteinTests` | unit test bundle | `com.jackwallner.protein.tests` |

App Group `group.com.jackwallner.protein`. iOS 17.0 / watchOS 10.0, Swift 6 strict concurrency, `DEVELOPMENT_TEAM: YXG4MP6W39`, RevenueCat SPM from 5.14.0. `project.yml` is `~/health/project.yml` with names substituted and the shared-source lists repointed (§5).

---

## 4. The one architectural call worth arguing about

`scoping.md` assumed a local SwiftData log of entries plus a WatchConnectivity queue to get wrist logs back to the phone, and multi-source reconciliation on top. Writing to HealthKit changes that, and simplifies it a lot.

**HealthKit becomes the single source of truth for our own entries too.**

```
log 30g on wrist  →  HKQuantitySample(.dietaryProtein, 30g, source = us)
                     written to the shared HealthKit store

today's total     =  sum of ALL dietaryProtein samples
                     WHERE source ∈ (us + user-selected external sources)

SwiftData          =  read-through cache for the complication only,
                      exactly the role DailyHealthRecord plays in Vitals
```

Why this is right:

- **Phone and Watch converge for free.** HealthKit syncs across paired devices. No WatchConnectivity queue, no write ordering, no "logged while phone was asleep" edge case. This deletes the single component in `scoping.md` §1 with no fleet precedent outside the archived Headache Logger.
- **Double-counting stops being a special case.** There is one sum over one set of sources. The `positioning.md` §4 "exclude our own source" rule was only needed because our entries lived somewhere else. They don't.
- **Freshness, the actual moat, is now trivially observable.** Every sample carries its source and its `endDate`, so "MacroFactor, 4m ago" is a read, not a bookkeeping exercise.

What it costs:

- Edit and undo mean deleting HealthKit samples. `HKHealthStore.delete` works on samples your own app wrote, so this is fine, but undo must hold the sample UUID.
- **Write authorization can be denied**, and unlike read auth, HealthKit tells us so honestly. If write auth is denied the app must still work: fall back to local-only SwiftData entries and add them to the sum. This fallback path needs to exist from day one, not be bolted on.
- Reads need `HKStatisticsOptions.separateBySource` (or an `HKSampleQuery` grouped by source), **not** the `queryStatisticsCollection` shape Vitals uses. This is the one place the Vitals port does not carry over cleanly.

---

## 5. Port map

### From `~/health` (VO2Max) - the app shell

| Piece | File | Change |
|---|---|---|
| 4-target XcodeGen layout | `project.yml` | Rename, repoint shared sources |
| Premium service | `Shared/Services/StoreService.swift` (330 ln) | Direct port. Permissive `isPro = !entitlements.active.isEmpty`, App Group mirror for widget gating, `setLocalOverride(isPro:)`, sim early-return |
| Paywall | `VO2Max/Views/PaywallView.swift` (564 ln) | Port, reskin copy |
| Trial offer sheet | `VO2Max/Views/TrialOfferSheet.swift` | Port. Honors `feedback_trial_page_cta_bar`: soft exit "Get Started", CTA pixel-identical to Continue |
| Onboarding | `VO2Max/Views/OnboardingView.swift` (606 ln) | Port structure, replace content with the three-audience fork |
| Review funnel | `Shared/Services/ReviewPromptTracker.swift`, `VO2Max/Views/ReviewPromptSheet.swift` | Direct port, new trigger (§7) |
| What's New | `Shared/Utilities/WhatsNew.swift`, `VO2Max/Views/WhatsNewSheet.swift` | Direct port |
| Ring | `VO2Max/Views/Components/ProgressRing.swift` | Direct port |
| Theme, notifications, goals, data, screenshot config, bundle version, review links | `Shared/` | Direct port |
| Watch app shell | `VO2MaxWatch/App.swift`, `Views/WatchTodayView.swift` | Port shell, replace body (§6 phase 3) |
| Watch complication | `VO2MaxWatchWidget/WatchComplication.swift` | Port, reformat for grams |

### From `~/vitals` (Total Calories) - the dietary layer

| Piece | File | Change |
|---|---|---|
| Dietary auth prompt | `Shared/Services/HealthKitService.swift:84` `requestDietaryAuthorization()` | Direct reuse. Avoids the double-prompt problem |
| Today's dietary read | `:204` `fetchDietaryEnergyToday()` | **Rewrite, not swap.** `.dietaryEnergyConsumed` → `.dietaryProtein`, `.kilocalorie()` → `.gram()`, and switch to `separateBySource` per §4 |
| Dietary history | `:227` `fetchDietaryHistory(days:)` | Swap type and unit, keep the shape |
| Conditional background delivery | `:537`, `:560-565` | Direct reuse, including the "first non-zero read means authorized" heuristic |
| App Group SwiftData cache | `Shared/Models/HealthRecord.swift` `DailyHealthRecord` | Same pattern, new fields: `dateString`, `date`, `proteinGrams`, `targetGrams`, `lastUpdated` |
| Complication number formatting | `VitalsWatchWidget/WatchComplication.swift` `ComplicationFormat` | Port the family-aware compaction, drop the calorie/step/deficit variants |

### Genuinely new

| Piece | Weight |
|---|---|
| `ProteinLogService` - write, delete, undo, write-auth-denied fallback | Medium |
| `ProteinReconciliation` - pure, source-grouped sum + freshness. Unit tested. | Medium |
| Sources screen (picker + per-source freshness rows) | Medium |
| Watch quick-add UI (presets + gram picker + undo) | Medium |
| `TrialWindow` - 7-day local access window (§7) | Small |
| Three-audience onboarding fork | Small |

---

## 6. Phases

Each phase ends at a checkpoint that can be verified, not just compiled. Sim work uses `agent-sim checkout protein`, headless, per the `ios-dev` skill.

**Phase 0 - scaffold.** `git init`, `.gitignore`, `project.yml`, entitlements, App Group, `Info.plist` with `UILaunchScreen`, `Protein.storekit`, `CLAUDE.md` + `AGENTS.md` symlink, fastlane and `scripts/testflight.sh` from the baseball template.
*Checkpoint:* `xcodegen generate` then a clean build of all four targets.

**Phase 1 - HealthKit layer.** Read with `separateBySource`, write, delete, auth (read and write separately), background delivery, the write-denied fallback. `ProteinReconciliation` as pure logic with unit tests over synthetic multi-source sample sets, including the same-source and stale-source cases.
*Checkpoint:* `ProteinTests` green. This is the phase where the tests matter most, because it is the only part that can be verified without a real device.

**Phase 2 - phone.** Onboarding fork, target setting, dashboard ring, sources screen, history, settings.
*Checkpoint:* sim screenshots analyzed against the strict checklist per `feedback_sim_screenshot_proof` - no em dashes in copy, no truncation, no clipped prices, single badges, real seeded values.

**Phase 3 - watch.** Today ring, quick-add presets, gram picker, undo, complication across all accessory families.
*Checkpoint:* headless paired-watch run per `reference_watch_sim_testing`. Log on the wrist, confirm the sample lands and the phone total moves. Gate any watch UI on `isPaired`, not `isWatchAppInstalled`.

**Phase 4 - monetization.** StoreService port, `TrialWindow`, paywall, trial offer sheet, review funnel.
*Checkpoint:* paywall rendered headlessly via a StoreKit Testing UI test per `reference_storekit_testing_paywall_render` (simctl alone only ever shows the empty state). Distinct `groupNumber` per sub in `Protein.storekit`. Never configure the prod `appl_` key on a sim run.

**Phase 5 - ship.** Icon, screenshots, ASC metadata against the placeholder record `6797089333`, Health & Fitness genre, the Regulated Medical Device declaration (UI-only, not in the API, per `reference_asc_medical_device_declaration`), first IAP submitted with the version per `reference_asc_first_iap_submission`, TestFlight.

---

## 7. Access model, and one thing that needs a decision

**Trial window.** First launch date in App Group `UserDefaults`. `hasAccess = isPro || daysSinceFirstLaunch < 7`. On expiry the app goes read-only: the target and today's number still display, logging and the sources picker are gated, **and the complication keeps updating**. That last part is deliberate. It costs nothing, and it is what keeps us on the wrist while the user reconsiders. The graveyard clones in `aso-plan.md` collect 1-star reviews for taking everything away.

**The overlap to resolve.** The fleet baseline sub carries a 1-week StoreKit intro offer, and `feedback_keep_monthly_trials` says do not strip it. Stacked on a 7-day local trial that is 14 free days.

My recommendation: keep both, and do not show the paywall on day 1. Run the local window silently, surface `TrialOfferSheet` around day 5, hard-wall on day 8. Rationale: the wrist habit is the product, and it needs a few days to form before we ask. The stacked 14 days is a feature in a category where every competitor asks immediately.

The alternative is to collapse to one trial by showing the offer sheet during onboarding and letting StoreKit own the 7 days. That optimizes trial *starts* over habit formation. Both are defensible. **Flagging rather than deciding.**

**Review funnel trigger.** Fire the enjoyment gate on the third day the user hits their target, never before. `requestReview()` only after Yes.

---

## 8. Risks, carried forward

1. **The import test is still unrun.** Jack chose import-as-headline, so the source picker and reconciliation UI are v1. I can build and unit-test them against synthetic samples, but whether MacroFactor / Cronometer / MyFitnessPal actually write readable `dietaryProtein` samples needs the 9-step real-device test in `README.md` §go/no-go. If two of three fail, the sources screen degrades to a mostly-empty list and the headline claim has to come off the product page before submission. **This is the single highest-value hour Jack can spend on this app.**
2. **Keyword volume is the binding constraint, not the build.** `protein tracker` at pop 58 / diff 65 is the hardest term any fleet app has taken on, guarded by Protein Pal at 9,880 ratings plus MyFitnessPal and Cal AI. Per `project_pricing_ppp_rollout`, install volume is already the fleet's limit. Nothing in this plan fixes that. Total Calories cross-promotion (`positioning.md` §6.5) remains the cheapest install source available and is still undecided.
3. **Trademark.** PROTEIN PAL is registered (filed Feb 2025). Only a Justia search was run, never a real USPTO clearance. `Protein Tracker - Grams Left` is descriptive and unlikely to collide, but the clearance is still open.
4. **Write-auth denial** is a real user state, not a theoretical one, and the fallback path in §4 has to ship in v1.
5. **App Review 1.4.1.** The bariatric and GLP-1 stories stay "track the target you were given". Never "we set your medical target". No treat, cure, or diagnose language anywhere in copy or metadata.

---

## 9. Closed since `positioning.md` §6

- **ProteinLoop** has no App Store listing. Store search returns unrelated apps. It is web-only, so "remaining" hero copy is clear.
- **Price band** resolved to fleet baseline, against the competitor research's $20-40/yr argument. Rationale: install volume is the constraint, so trial starts matter more than revenue per install.
- **Port base** resolved. VO2Max shell over Vitals shell, because VO2Max has `OnboardingView`, `TrialOfferSheet`, `PlusTabView` and `WhatsNewSheet` and Vitals does not.
