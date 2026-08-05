# Protein app — build scoping

> Written 2026-08-04. Companion to `README.md` (product/HealthKit dossier) and `aso-plan.md` (market reality).
> Nothing here commits to a positioning. It costs out the options.

---

## 1. What we can reuse, and what is genuinely new

The README claims Vitals/Total Calories has "almost the exact skeleton". Verified — it does, for the **read** half. It has none of the **write** half, and the write half is the whole product.

### Verified reusable from `~/vitals` (Total Calories)

| Piece | File | Fit |
|---|---|---|
| Dietary HealthKit read | `Shared/Services/HealthKitService.swift:204 fetchDietaryEnergyToday()` | Swap `.dietaryEnergyConsumed` → `.dietaryProtein`, `.kilocalorie()` → `.gram()`. Statistics-collection query is already the right shape. |
| Separate dietary auth prompt | `requestDietaryAuthorization()` :84 | Direct reuse. Avoids the double-prompt problem. |
| Conditional dietary background delivery | :560-565 + `dietaryBackgroundDeliveryEnabled` flag :537 | Direct reuse, including the "first non-zero read means authorized" heuristic. |
| Daily history | `fetchDietaryHistory(days:)` :227 | Direct reuse. |
| SwiftData App Group cache → complication | `Shared/Models/HealthRecord.swift` `DailyHealthRecord` | Same pattern, new fields. |
| 4-target XcodeGen layout | `project.yml` (iOS app + iOS widget + watchOS app + watch widget) | Direct template. |
| Goals, StoreService, ReviewPromptTracker, NotificationService, theme | `Shared/Services/` | Direct reuse. |
| Freemium price point | `Vitals.storekit`: $1.99/mo, $14.99/yr | Fleet baseline. |

### New, not in any fleet app

| Piece | Why it is new | Rough weight |
|---|---|---|
| **Write path** — a local protein log with entries, edit, undo, day rollover | Every fleet health app is read-only from HealthKit. Vitals never writes a nutrition record. | Large |
| **Saved foods / saved meals** store + editor | No precedent | Medium |
| **Watch input UI** (quick-add grid, saved list, gram picker, undo) | Fleet Watch apps are all display-only complications. Headaches archive has one-tap Watch input, which is the closest precedent. | Large |
| **WatchConnectivity write queue** (Watch logs while phone is asleep) | Only precedent is the archived Headache Logger `WatchConnectivityController` | Medium |
| **Multi-source reconciliation** (our entries + one chosen external HealthKit source, no double counting) | Genuinely novel, and it is the reliability moat the README identifies | Medium-Large |
| **App Intents / Siri** "log 30 grams of protein" | No fleet precedent | Medium |
| Food database or barcode | Only if we decide to own it | Very Large — see §3 |

**Honest read:** this is not a Vitals reskin. It is roughly Vitals' read layer plus a whole logging app on top. The reusable part is maybe 35% of the build.

---

## 2. The three strategic options, costed

### Option A — "Pure protein, no calories" (take the position Protein Pal is vacating)

Protein Pal's subtitle is now `Calorie Counter & AI Scanner`. The leader has left the narrow position.

- **Promise:** one number, no calorie guilt, no food diary, no AI. Wrist-first.
- **Keyword:** fights `protein tracker` (pop 58, diff 65) head-on. We will not rank there for a long time.
- **Wins on:** product page conversion, Watch, speed, retention, review velocity.
- **Risk:** the honest one — we may simply never get impressions. Per `[[project_pricing_ppp_rollout]]`, install volume is already the fleet's binding constraint, and this is the hardest keyword any fleet app would have taken on.
- **Build:** full write path + Watch input + HealthKit import. No database.

### Option B — Audience entry (`bariatric`, or GLP-1, or seniors)

- **Promise:** the protein target *your clinic gave you*, tracked in seconds.
- **Keyword:** `bariatric` pop 14 / diff 17 is winnable below Baritastic. GLP-1 and senior protein vocabularies both measured at floor (pop 5) so they are *positioning*, not *discovery*.
- **Wins on:** a real underserved user with a hard externally-assigned number, plus higher willingness to pay.
- **Risk:** Baritastic (95K ratings, free, Metagenics-distributed) defines the category. We would be the fast wrist companion, not the replacement. Also pulls toward the Medical genre and closer to App Review 1.4.1 health-claim scrutiny.
- **Synergy:** Jack already owns `Simple GLP` — a protein app could cross-promote, and GLP-1 muscle-loss is a live 2026 concern.
- **Build:** same as A, plus stage-aware targets (post-op phases) if bariatric.

### Option C — Do not ship standalone; make protein a Total Calories feature

- Total Calories already has: ASC presence, `dietaryEnergyConsumed` plumbing, a Watch complication, an App Group cache, keyword ground on the calorie lane, and existing installs.
- Adding a protein ring/complication there costs a fraction of a new app and takes zero new keyword risk.
- **Cost:** gives up a second App Store listing (a real acquisition asset in this fleet) and muddies Total Calories' TDEE/burn position (`[[project_total_calories_aso]]`: it is a burned-energy app, not a food logger — adding protein *logging* would contradict that).

---

## 3. Scope forks that change the build size materially

| Fork | Cheap answer | Expensive answer |
|---|---|---|
| **Food data** | No database. Saved foods the user creates once + gram quick-add. | Own/license a food DB + barcode. Very large, ongoing cost, and directly attacks the wall apps. |
| **AI logging** | None. Explicit anti-AI positioning ("no photo guessing"). | Photo/voice/text estimation. Every graveyard app has this; it is table stakes in the gold rush and a differentiator in neither direction. |
| **HealthKit writing** | Read-only import at launch. | Write our samples back, which forces same-source exclusion logic. README §"HealthKit writing policy" already specifies the correct rule. |
| **Watch** | Complication + quick-add only. | Full standalone Watch app with history and editing. |
| **Sync** | Local only, App Group, no account. Matches every fleet app except Bond/Aging. | CloudKit or Supabase. Not justified for a single-user daily number. |

---

## 4. What still needs real-device verification (from README §go/no-go)

Unchanged and still worth doing before any build: confirm at least two of MacroFactor / Cronometer / MyFitnessPal actually write `dietaryProtein` samples readable by us, per the 9-step plan in `README.md`. This is cheap (one afternoon, real device, real apps) and it decides whether "import from your existing logger" is a headline feature or a footnote.

Note this test does **not** gate Option B, where the user is likely not running a full logger at all.

---

## 5. Decisions (2026-08-04)

Resolved by Jack. See `docs/positioning.md` for rationale.

| Question | Answer |
|---|---|
| Positioning | **Option A** — take the position Protein Pal is vacating |
| Form factor | **Watch is the product**, phone is setup + history |
| Food data | **Saved foods + gram quick-add only**. No database, no barcode. |
| AI logging | **Explicitly out**, and marketed as such |
| Audience | **All three** — lifters, GLP-1, post-bariatric — as one product with an onboarding fork |

This selects the **largest** of the three build shapes in §1: watch-first means the Watch input UI and the WatchConnectivity write queue (the two components with no fleet precedent outside the archived Headache Logger) are both v1, not v2.

### Still open

1. **Price band** — fleet baseline $1.99/mo, $14.99/yr vs. the $20-40/yr band the competitor research argues for. Decide before the paywall is built.
2. ProteinLoop App Store check, before name/hero copy lock.
3. Real-device HealthKit import test (§4) — headline feature or footnote.
4. Trademark clearance (PROTEIN PAL is registered).
5. Total Calories cross-promotion.
