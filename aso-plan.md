# aso-plan.md — Protein app (pre-launch ASO scoping)

> Written 2026-08-04. Pre-launch. ASC placeholder `Protein App Placeholder` (`6797089333`), bundle `com.jackwallner.protein`.
> Astro research app: **Protein (pre-launch research)**, temporary `appId 122`, store `us`.
> Methodology: `~/ios/aso/astro-setup-process.md` + the fleet keyword method (winnability ceiling + SERP intent guardrails).

---

## 0. TL;DR — the finding that should drive the product decision

**The protein category is a one-keyword category.**

Of 30 protein-vocabulary terms measured in Astro, exactly **one** carries real search volume:

| Keyword | Popularity | Difficulty | Verdict |
|---|---:|---:|---|
| `protein tracker` | **58** | **65** | The only real door. Guarded. |
| `track protein` | 19 | 46 | Secondary, more winnable |
| `protein` | 7 | 44 | Thin |
| everything else | **5** (floor) | — | No measurable demand |

"Popularity 5" is Astro's floor and means *no measurable search demand*. This is the same signature that killed the eldercare vocabulary for Aging (see `[[project_aging_medlist]]`), with one crucial difference: **eldercare had no head term at all; protein has one strong one.**

The head term is guarded by a real incumbent plus two giants:

| Rank on `protein tracker` | App | Ratings (US) |
|---:|---|---:|
| 1 | Protein Tracker: Protein Pal | 9,880 |
| 2 | MyFitnessPal | 2,348,449 |
| 3 | Protein Tracker. (Kai Oelfke) | 1,670 |
| 4 | Cal AI | 348,920 |
| 6 | Cronometer | 95,642 |

And below rank 5 the SERP is a **gold-rush graveyard**: `Proteebeast` (5★ count), `ProteinYeti` (4), `Protino` (1), `Protify` (3), `Protein8` (3), `ProteinMeter` (1), `ProteinMax` (0), `ProteinFirst` (0), `ProteinGoal` (0), `Panda Protein Goal Tracker` (0), `ProteinPenguin` (0), `Protein Intake Tracker` (0). At least a dozen 2025-2026 launches with near-zero traction all fighting the same single keyword.

**Read this correctly:** the graveyard is not proof the niche is dead. It is proof that *the generic protein-counter product is dead* — a dozen people shipped the obvious app and none of them broke through Protein Pal. Anything we ship has to be a different product, not a nicer version of the same one.

---

## 1. Full keyword measurement (Astro, us, 2026-08-04)

### Protein vocabulary

| Keyword | Pop | Diff | Note |
|---|---:|---:|---|
| protein tracker | 58 | 65 | **head term** |
| track protein | 19 | 46 | secondary |
| protein | 7 | 44 | |
| protein calculator | 6 | 23 | low diff, no volume |
| protein intake | 5 | 23 | floor |
| protein counter | 5 | 40 | floor |
| protein goal | 5 | 44 | floor |
| daily protein | 5 | 11 | floor |
| high protein | 5 | 46 | floor |
| protein log | 5 | 11 | floor |
| protein app | 5 | 40 | floor |
| protein diet | 5 | 21 | floor |
| protein shake | 5 | 43 | floor |
| protein intake tracker | 5 | 40 | floor |
| protein per day | 5 | 11 | floor |
| protein grams | 5 | 11 | floor |
| how much protein | 5 | 9 | floor |
| protein reminder | 5 | 17 | floor |
| eat more protein | 5 | 11 | floor |

### The Watch/widget angle has ZERO acquisition value

| Keyword | Pop | Diff |
|---|---:|---:|
| protein watch | 5 | 13 |
| protein widget | 5 | 15 |
| protein remaining | 5 | 11 |
| apple watch food | 5 | 72 |

This is consistent with every other app in the fleet (`apple watch headache` pop 5, `apple watch posture` pop 5, `apple watch calories` pop 5, `apple watch vo2 max` pop 5). **Nobody searches the App Store for a Watch complication.**

The README's watch-first thesis is therefore a **product/retention/conversion wedge, not a discovery wedge.** It can win the user once they are on the page. It will not bring them to the page. Any plan that assumes "watch-first = ASO differentiator" is wrong.

### Broad nutrition terms — all walls

| Keyword | Pop | Diff |
|---|---:|---:|
| calorie counter | 65 | 78 |
| macro tracker | 60 | 80 |
| nutrition tracker | 55 | 80 |
| meal tracker | 55 | 81 |
| macros | 46 | 73 |
| food log | 7 | 65 |
| macro counter | 6 | 78 |

Volume exists here but difficulty 73-81 against MFP/Cal AI/Cronometer is unwinnable for a solo launch. Do not chase.

### Adjacent audience vocabularies

| Keyword | Pop | Diff | Note |
|---|---:|---:|---|
| **bariatric** | **14** | **17** | Real demand, low difficulty. Best non-protein door found. |
| protein bariatric | 5 | 19 | floor |
| sarcopenia | 5 | 11 | floor |
| glp1 protein | 5 | 11 | floor |
| protein for seniors | 5 | 11 | floor |
| vegan protein | 5 | 5 | floor |
| muscle tracker | 5 | 46 | floor |
| gym nutrition | 5 | 44 | floor |
| bulking | 5 | 52 | floor |
| cutting diet | 5 | 49 | floor |

`bariatric` pop 14 / diff 17 is the only genuinely winnable term with above-floor demand in the whole set. Caveat: **Baritastic** owns it with 94,897 ratings, is free, is clinic-distributed by Metagenics, and is category-defining. Ranks 2-10 on that SERP drop to 50, 40, 231, 9, 77 ratings, so there is room *below* Baritastic but not *instead of* it.

---

## 2. SERP intent guardrails

Every protein term tested returns protein/nutrition apps. **No homograph risk** (unlike `barometric forecast` → weather apps for Headaches, or `caregiver` → false friend for Aging).

| Term | Top-of-SERP class | Guardrail |
|---|---|---|
| `protein tracker` | protein + calorie trackers | Intent PASS, winnability FAIL (diff 65 + Protein Pal wall) |
| `track protein` | MFP, Protein Pal, Cal AI, small protein apps | Intent PASS, winnability MARGINAL (diff 46) |
| `protein goal` | Protein Pal, MFP, Protein Log, Panda | Intent PASS, no volume |
| `protein intake` | pure protein apps + graveyard | Intent PASS, no volume |
| `bariatric` | Baritastic + bariatric-specific trackers (Medical genre) | Intent PASS, winnability GOOD below rank 1 |

Note: the `bariatric` SERP is mostly **Medical** genre, not Health & Fitness. Category choice matters if we go that way.

---

## 3. Competitor tiers

| Tier | Apps |
|---|---|
| **WALL** | MyFitnessPal (2.35M★), Cal AI (349K★), Cronometer (96K★), Lose It (770K★), MyNetDiary (160K★), Baritastic (95K★ on the bariatric lane) |
| **CATEGORY INCUMBENT** | Protein Pal (9,880★, 4.7) — the app to actually beat. Note its subtitle has drifted to `Calorie Counter & AI Scanner`, i.e. it is abandoning the pure-protein position |
| **REAL PEERS** | Protein Tracker. (1,670★, 4.8, indie, Kai Oelfke), Protein Log (292★), Foodnoms (7,446★), MacrosFirst (19,887★) |
| **GRAVEYARD** | ~12 apps at 0-11 ratings launched 2025-2026, all named `Protein<Something>` |

**The most useful competitive fact on this page:** Protein Pal, the leader, changed its subtitle to `Calorie Counter & AI Scanner`. The incumbent is walking away from the narrow protein position to chase the AI-calorie-scanner gold rush. That vacates the "actually just protein, no calorie guilt" position. Whether that position has enough buyers is the open question.

---

## 4. Name candidates and what is taken

Taken/burned: Protein Pal, Protein Tracker., Protein Log, ProteinLog, Protein Flow, ProteinFirst, ProteinGoal, ProteinMax, ProteinMeter, ProteinYeti, Proteebeast, Protino, Protify, Protein8, ProteinPenguin, Hello Protein, Amino, DailyP, Panda Protein Goal Tracker.

Every cute `Protein<Noun>` construction is spent. The fleet convention (`Total Calories - Daily Tracker`, `Headache Tracker - One Tap`, `Streak Finder: Health Habits`) is descriptive-first, which is the right instinct here: the name should carry `protein tracker` as literal text since that is the only term with volume, and the subtitle should carry the differentiator.

Working shape: `Protein Tracker - <differentiator>` with subtitle stating the wedge.

---

## 5. What this means for the go/no-go

The README's go/no-go test was technical (do two mainstream apps write `dietaryProtein` to HealthKit). That test is still worth running, but it is **not the binding constraint**. The binding constraint is:

> There is one keyword worth 58 popularity, it is difficulty 65, an incumbent with 9,880 ratings sits on it, and a dozen 2026 launches already failed to move it.

Winning requires one of:

1. **Take the position Protein Pal is vacating** (pure protein, zero calorie counting, no AI scanner) and win on execution + Watch + speed. Fights for the same keyword but with a genuinely different product promise.
2. **Enter through a different vocabulary** (`bariatric` pop 14 / diff 17 is the only measured candidate) and let `protein tracker` be a secondary keyword-field term we never expect to rank on.
3. **Do not launch standalone.** Ship protein as a feature of Total Calories, which already has ASC presence, HealthKit dietary plumbing, a Watch complication, and keyword ground on the calorie lane.

These are mutually exclusive at the metadata level. Pick before building.

### DECIDED 2026-08-04: Option 1

Take the position Protein Pal is vacating. Fight `protein tracker` on execution rather than keyword muscle, with `track protein` (pop 19 / diff 46) as the realistic near-term rank. Audience stories (lifter / GLP-1 / post-bariatric) live in screenshots and description; `bariatric` goes in the keyword field as the one above-floor audience term. Full rationale in `docs/positioning.md`.

**Metadata consequences to honor:**

- Name must contain the literal string `protein tracker` — it is the only term with volume.
- Subtitle carries the wedge (one number / wrist / no calorie counting) and must be SERP-validated per §2 before it ships.
- Do NOT put `calorie`, `macro`, `AI`, or `scanner` in the subtitle. Those steer Apple toward the diff 73-81 wall SERPs and contradict the position.
- `bariatric` in the keyword field only. GLP-1 and senior terms are floor-demand: description and screenshots, never the keyword field.

---

## 6. Astro housekeeping

- Research app `122` is **temporary**. On launch, migrate to the real ASC id `6797089333` (same pattern as Posture `104` → `6768514450`, see `[[reference_astro_tracking]]`).
- Keywords tracked: 44 across protein, watch, broad-nutrition, and adjacent-audience vocabularies.
- Not yet tagged `deployed`/`target`/`wall` — do that once positioning is chosen.

---

## 7. Shipped metadata (2026-08-14)

Live on the 1.0 draft, verified against ASC:

```
Name:     Protein Tracker - Grams Today                       29/30
Subtitle: Daily intake goal, on Watch                         27/30
Keywords: bariatric,calculator,counter,log,target,muscle,
          lifting,gym,shake,whey,healthkit,import,eat,food,diet  100/100
```

The keyword field changed 2026-08-14: added `calculator`, `target`, `import`,
dropped `fitness`, `weight`, `meal`. The three drops each land on a §1
difficulty 78-81 wall. `calculator` is honest (`ProteinTargets.suggestedTarget`
really does compute grams from body weight at a g/kg ratio) and cheap at diff
23, though note rank 3 `Protein Tracker.` already runs the subtitle
`Protein Calculator & Counter`, so it is contested. `import` and `healthkit`
carry the multi-source story, which is the one thing the graveyard clones in §0
do not have.

The subtitle already indexes `daily`, `intake`, `goal` and `watch` for free.
Do not re-buy those words inside the 100 characters.

**Two rewrites that keep getting proposed and must keep being rejected:**

1. **A Watch-first subtitle** (e.g. `Quick Add for Apple Watch`). It spends all
   30 characters on the vocabulary §1 measured at the floor: `protein watch`
   5/13, `protein widget` 5/15, `apple watch food` 5/72, matching every other
   app in the fleet. Watch-first is the conversion wedge, so it belongs in
   screenshot 1 and the description, not in the 30 characters that also have to
   index. Separately, `Apple Watch` is an Apple trademark and metadata rules bar
   trademarked terms from the name and subtitle; the bare word `Watch`, which is
   what ships, carries the same meaning with none of the review risk.
2. **`glp1` in the keyword field.** §5 already rules it out. The measured 5/11
   is for the phrase `glp1 protein`, not the bare token, and every audience term
   below `bariatric` is at the floor. It lives in the description and
   screenshots.

General trap behind both: §1 measures **phrases**. `protein calculator` 6/23 is
not a reading for the token `calculator`, and quoting it as one manufactures
demand that was never measured.
