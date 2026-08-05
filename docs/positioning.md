# Protein app — positioning decisions

> Decided 2026-08-04 by Jack. This is the locked direction. `README.md` = HealthKit dossier, `aso-plan.md` = keyword reality, `docs/scoping.md` = build cost, `research/competitors.md` = competitor detail.

---

## 1. The four decisions

| Decision | Choice |
|---|---|
| **Positioning** | Take the position Protein Pal is vacating: pure protein, no calorie counting, no AI. Fight `protein tracker` on execution, not on keyword muscle. |
| **Form factor** | Watch is the product. Phone is setup, saved-food editing and history. |
| **Scope** | Saved foods + gram quick-add only. No food database, no barcode, **explicitly anti-AI**. |
| **Audience** | Three, served by one product: lifters/strength trainees, GLP-1 users, post-bariatric patients. |

---

## 2. Why this is coherent and not three apps

Three audiences, one product, because all three share the identical job:

> Somebody gave me a protein number. Am I going to hit it today, and can I log the thing I always eat without opening a food diary?

What differs is only **where the number came from** and **what happens if you miss it**:

| Audience | Number comes from | Cost of missing | Their repeat foods |
|---|---|---|---|
| Lifter | self-set, ~1.6-2.2 g/kg | slower gains | shake, chicken, eggs, bar |
| GLP-1 user | clinician or the internet, ~60-100g floor | **lean mass loss** (up to 40% of GLP-1 weight loss can be lean mass without adequate protein) | shake, yogurt, cottage cheese, small portions |
| Post-bariatric | **clinic-assigned**, 60-80g, phased post-op | complication risk, clinic follow-up | shake, purees, soft protein, tiny portions |

So the product is one target + one log + one wrist surface. The audience shows up in exactly three places:

1. **Onboarding fork** — "Why are you tracking protein?" branches the suggested target and the starter saved-food set. Nothing else in the app changes.
2. **Screenshots / product page** — the acquisition surface, where the audience story actually earns the install. This is where the three stories pay off, since the SERP will not distinguish them.
3. **Keyword field** — `bariatric` is the only audience term with above-floor demand (pop 14 / diff 17); GLP-1 and senior terms are all at the floor, so they live in the description and screenshots, not the keyword field.

**Guardrail:** do not build three onboarding flows, three paywalls, or three theme sets. One product, one number, three reasons.

---

## 3. What "the position Protein Pal is vacating" actually means

Protein Pal (9,880 ratings, the category leader) now has the subtitle `Calorie Counter & AI Scanner`. It left. Every one of the ~12 clones that launched in 2025-26 chased it into the AI-scanner gold rush and none of them broke through.

So the vacant position is the *original* one, and our differentiators are the things all of them abandoned:

| We do | They do |
|---|---|
| One number: grams remaining | Calories, carbs, fat, "nutrition score" |
| Your five foods, one tap | 4,000-row database you scroll |
| Deterministic grams you set once | AI photo estimates that are wrong and get reviewed as wrong |
| Wrist-first, complication is the product | Phone-first, Watch is an afterthought or absent |
| Import from your existing logger via Apple Health | Replace your existing logger |

**Anti-AI is a marketing asset, not just a scope cut.** "No photo guessing" is a differentiator precisely because a dozen competitors ship guessing and get reviewed for it.

---

## 4. Competitive facts that constrain this (from `research/competitors.md`)

**MacroFactor closed most of the wedge, and this is more current than the README says.** It shipped a real Watch app (v5.4.0, Sept 9 2025, watchOS 11+, confirmed on the App Store listing) and per its own site ships protein/carb/fiber complications plus wrist voice logging, GA around January 2026. It is the one mainstream tracker that genuinely does what we propose.

**Why this does not kill the plan:** MacroFactor is $71.99/yr with **no free tier**, 20K ratings, and is a full expenditure-model macro coach. It is not competing for someone who wants one number for a few dollars. It does mean "first to put protein on the wrist" is no longer true, so the claim has to be **"the simplest and the most reliable,"** never "the only."

**Everyone else still has the gap open:**

- **Protein Pal** (9,880 ratings, the actual keyword incumbent): **no Watch app at all.**
- **Cronometer**: a "remaining macros" forum request open since **April 2018**, still bumped in March 2024. A separate open bug from Jan 2025 has the Watch "Remaining" value disagreeing with the phone.
- **Bevel**: its own public feedback board lists watch-face macro complications as **status Planned, 74 votes**, contradicting its marketing.
- **MyFitnessPal**: does ship a Protein complication, but a **June 18 2026** MacRumors thread has a user asking whether it is "just a poorly written app" because it will not update. View-only, no wrist logging.
- **Yazio**: no macro complication (water only). **Lose It / MyNetDiary / Lifesum**: unconfirmed or unreliable.
- **GLP-1 tracker sub-category** (GlucoPal, GLP-1.COM, MeAgain, Glone, OzemPro, Weightly, ShotFit): a dozen apps, most leading with protein, and **no evidence any has Apple Watch support.**

**Freshness is the moat, not novelty.** Every one of those complaints is about a number that is stale or wrong, not about a missing feature. The README's multi-source reconciliation plus a visible last-updated state is the thing to get right.

---

## 5. Naming

Every `Protein<Noun>` construction is spent: Protein Pal, Protein Log, ProteinLog, ProteinLoop, Proteinful, Proto, Protify, Protino, Protein8, ProteinYeti, Proteebeast, ProteinMeter, ProteinMax, ProteinFirst, ProteinGoal, ProteinPenguin, Gramo, PRTN, GainzKeepr, Amino, DailyP, WheyGPT, MacroWhiz.

**Concept collision to check before finalizing copy:** [ProteinLoop](https://proteinloop.app/) frames its hero number as "171g Remaining," the same mechanic. Claimed free-forever, appears iPhone-only, no App Store listing located. Search the store directly under that name before committing to hero copy that echoes "protein remaining."

Fleet convention is descriptive-first (`Total Calories - Daily Tracker`, `Headache Tracker - One Tap`). Since `protein tracker` is the only term with volume, it should appear as literal text in the name, with the subtitle carrying the wedge.

Working shape:

```
Name:     Protein Tracker - <differentiator>
Subtitle: <one number / wrist / no calorie counting>
```

Do not lock this until the ProteinLoop check is done and the subtitle is SERP-validated per `aso-plan.md` §2.

---

## 6. Open items, in order

1. **Price band.** Fleet baseline is $1.99/mo, $14.99/yr (Vitals). The protein clones sit at $3-40/yr with negligible traction; the mainstream trackers sit at $60-100/yr. The competitor report argues for a **$20-40/yr** band: cheap next to a $72 MacroFactor, not a toy like the $3 clones. This is a live decision against fleet convention.
2. **ProteinLoop App Store check** before name and hero copy lock.
3. **Real-device HealthKit import test** (README §go/no-go, 9 steps). Decides whether "import from your existing logger" is a headline or a footnote. Note this matters much less for the GLP-1 and bariatric audiences, who are less likely to be running MacroFactor at all.
4. **Trademark clearance.** PROTEIN PAL is registered (filed Feb 2025). Only one Justia search was run, not a real USPTO clearance.
5. **Total Calories cross-promotion** — undecided, and it is the cheapest install source we have.

---

## 7. Explicitly out of scope for v1

Food database, barcode scanning, AI photo/voice estimation, calorie tracking, macro tracking beyond protein, coaching, meal plans, social, cloud accounts, and any claim to treat, cure or diagnose (App Review 1.4.1 applies; the bariatric and GLP-1 stories must stay "track the target you were given," never "we set your medical target").
