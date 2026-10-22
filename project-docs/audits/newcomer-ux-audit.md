# Caffeine Tracker: Bedtime, newcomer persona audit

Persona: a first-time user who does not know the app's terminology and wants one useful result immediately.
Run: shift-audit-caffeine-newcomer-2-1792690256 (continues run 1; the UI test file NewcomerAuditUITests.swift was committed there).

## Evidence status (read this first)
- Runtime: NOT obtained in this run. `gh-sim test --only CaffeineUITests/NewcomerAuditUITests` was dispatched as GitHub run 39823455018 (id `caffeine@shift-audit-caffeine-newcomer-1-1792674560-mbpro0853-1022-103124-905`, 3 tests: first run + log + all tabs, skip Health then log, accessibility-XL onboarding). The first foreground watcher died at the 10 minute tool limit, and later `gh-sim get` calls waited behind the fleet-wide GitHub queue while the shared GitHub API returned HTTP 403 rate limit errors. No results folder had arrived at the time of writing.
- Every finding below is therefore SOURCE-ONLY (file and line cited) unless stated. Nothing here is a frame-rate judgement; motion was not measured.
- To finish: `gh-sim get <id above>`, then review `~/.gh-sim/results/<id>/shots` and `attachments` (`tap-targets.txt` has frame sizes), and promote or demote the findings below.

## Findings (most severe first)

### 1. Welcome promise contradicts the core action (Medium, source-only)
- Repro: install, read step 1 ("Log a drink in one tap", bullet "One tap to log, one tap to undo"), finish onboarding, tap Drip coffee on Now.
- Actual: the tap opens the Drink preview sheet (`CaffeineViews.swift` quickAdds sets `preview`), a second tap on "Log N mg" is required, and the sheet shows WITHOUT / WITH DRINK comparisons, a latest-time line and a range before the user has logged anything.
- Impact: a newcomer who just wanted to record a coffee meets a decision screen full of unexplained terms ("bedtime preference", "reference range") and feels the promise was false. Three taps, not one.
- Fix: reword step 1 to "Tap a drink, see what it does to tonight, then log it" or add a true one-tap log path (long press, or a plus button on each chip). Keep the preview as the default if that is the product choice, but lead the sheet with the Log button visible without scrolling.
- Files: `Caffeine/Views/OnboardingView.swift` welcomePage, `Caffeine/Views/CaffeineViews.swift` quickAdds.

### 2. Five onboarding steps and two system prompts before any result (Medium, source-only)
- Repro: first launch. Steps: welcome, bedtime wheel, Apple Health explainer plus system sheet, body data explainer, Caffeine+ pitch. Only then the Now screen, which shows "0 mg" and "Nothing in the last N hours."
- Impact: the user asked "how much caffeine is in me" and has typed nothing. Steps 4 and 5 (body insights, subscription) are for a feature that needs 21 nights of data (finding 3), so they are pure delay for a newcomer.
- Fix: cut the first run to welcome, bedtime and Health. Offer body data from the Cutoff tab (already has a connect card) and the pitch after the first logged drink. Alternatively default bedtime and show Now immediately, asking Health at first log.
- Files: `OnboardingView.swift` (totalSteps = 5), `BodyInsightsView.swift` connectCard.

### 3. The headline Cutoff tab cannot give a newcomer a result for three weeks (Medium, source-only)
- Repro: Cutoff tab after skipping body data shows "Connect Apple Health" card; after connecting with no history shows "N of 21 nights" (`CaffeineInsights.minimumCutoffNights = 21`).
- Impact: the tab the product is positioned on delivers nothing on day one, and the card is mostly questions a newcomer does not yet hold ("HRV", "resting heart rate", "a dose"). The dashed example (92 mg, 41 minutes shorter) is clearly labelled "not your data", which is good, but there is no hint of how long to wait other than the number 21.
- Fix: say "about 3 weeks of logging and sleep data" in plain words on the card, and when Health already holds sleep history, state how many nights were found immediately.

### 4. Unexplained terminology on the main screen (Medium, source-only)
- Strings: "4-6h range" (Now), "MODEL 5.0 hour half-life" (Today card), "bedtime preference", "Reference range at bedtime" and "A preference is a number you chose" (preview sheet), "Stop guessing at the 5 hour average", "HRV" (Cutoff), tab name "Cutoff".
- Impact: a newcomer cannot tell what "estimated remaining now" versus "at bedtime" versus "4-6h range" each mean or which one to act on. There is no one-line answer such as "Safe to sleep" (which the product correctly avoids), but there is also no plain "what this means" line.
- Fix: one plain sentence under the bedtime figure, for example "How much may still be in your system when you go to bed at 10:30 PM. The range shows 4 to 6 hour half-lives." Replace "half-life" in the Today card with "clears at about half every 5 hours". Spell out HRV once.
- File: `CaffeineViews.swift` remainingCard, todayCard, forecastCard.

### 5. Undo row can sit stale and fail silently (Low to Medium, source-only)
- `undoRow` shows only while `Date.now - lastLoggedAt < 120 s`, but nothing re-renders the view at 120 s, so the row remains until something else changes state.
- `undoLast()` returns false when HealthKit deletion fails (for example the entry was written but delete permission differs), and the Undo button ignores the result: no message, the row stays.
- The row also sits below the "Preview another drink" button, so on a small phone with the chart visible it may be below the fold after logging. Runtime check pending (test1 `now-after-log` screenshot).
- Fix: schedule a task that clears the row at 120 s (TimelineView or a timer), show a short error when undo fails, and consider placing the confirmation at the top of the scroll content or as a toast.
- Files: `CaffeineViews.swift` undoRow, `Shared/Services/CaffeineLogService.swift` undoLast.

### 6. Deleting a logged entry is hidden behind a long press (Low, source-only)
- "YOUR LOG" rows only offer delete through `.contextMenu`, plus the Edit sheet button. There are no swipe actions, and the footer hint says "Tap an entry to change the drink, amount, or time" without mentioning delete.
- Fix: add `swipeActions` (needs a List) or mention "Hold to delete" in the hint.

### 7. Health sheet decline path is correct but quietly different (Low, source-only)
- Tapping "Not now" on step 3 skips the system sheet; logging then lands in the local queue and Now shows the amber banner "1 entry is saved on this device only". Wording is accurate. A newcomer may read "saved on this device only" as the whole app being broken. Runtime check pending (test2 `now-logged-no-health`).
- Fix: lead with what works ("Logged. It will sync to Apple Health once you allow it"), then offer the Connect action as a button in the banner, not just "Retry now".

### 8. Large text onboarding (unverified)
- `page(...)` wraps content in a ScrollView so text should not clip, but the primary button footer is fixed and the Caffeine+ step stacks soft exit, price, disclosure and the legal row above and below the button. At Accessibility XL this may push the primary button into a small scroll viewport. test3 (`large-health`, `large-welcome`) would confirm. Not verified.

## Things that work for this persona (source-level)
- Onboarding copy states plainly what the Health permission is for and that declining is allowed.
- Empty Now card names its state ("Nothing in the last N hours. Log a drink and this fills in.").
- The estimate provenance row explains non-zero first launch numbers.
- The Cutoff example is explicitly labelled as not the user's data.
- Disclaimers use "may remain", "modeled", "estimate" consistently, no medical claims.

## Suggested next actions (ordered)
1. Finish runtime evidence with `gh-sim get` and update findings 5, 7, 8.
2. Fix finding 1 wording (cheap, removes a false promise).
3. Plain-language line under the bedtime figure (finding 4).
4. Shorten first run (finding 2).
