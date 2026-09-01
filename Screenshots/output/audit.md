# Screenshot audit: caffeine

Status: **PASS**
Disposition: **RELEASE-READY**
Target: `iphone_69` at `1320x2868`
Capture status: `ok`

This report combines file-spec checks with an independent thumbnail and OCR pass. Open each `contact-sheet.png` and `search-grid.png` before approving a set.

## Warnings

- midnight: 06-model.png: thumbnail OCR missed header words ['tune', 'the', 'your']

## Market brief

- Category: Caffeine trackers and sleep planning tools
- Audience: Coffee, tea, pre-workout, and energy drink users who want to understand timing before another dose
- Problem: A basic caffeine log records the decision after it happens and leaves the user to translate intake into a bedtime impact
- Advantage: Caffeine Tracker reads the sleep already in Apple Health and finds the bedtime estimate above which this person's own recorded sleep ran measurably shorter, then previews a proposed dose against it before anything is logged
- Competitive context: The category ships drink logs and population half-life decay curves. This app derives a per-person cutoff from that person's own sleep record, withholds it until 21 nights exist, and reports no measurable difference when that is the answer

## Sets

| Set | Status | Frames |
| --- | --- | ---: |
| `midnight` | pass | 6 |

## Review contract

- Contract: `single-header-benefit-story-v3`.
- Every creative frame has exactly one large, period-free header capped at two lines. Eyebrows and subheaders are forbidden.
- Phone frames use at least 50% of the canvas for literal UI evidence.
- The selected submission set contains six to eight frames. Other sets and background variants are review alternatives, not additional ASC inventory.
- Every visible header pitches a concrete benefit backed by a per-frame problem, advantage, search term, and literal UI proof.
- The first three frames must communicate separate market value at search scale.
- Every frame declares source, source_evidence, capture_flow, device, and evidence_status. Canonical frames map one-to-one to capture-report records.
- The app screen must be real capture evidence from the referenced build.
- Health and wellness copy must stay complementary and non-diagnostic.
- Re-run the audit after every copy, source, or layout change.
