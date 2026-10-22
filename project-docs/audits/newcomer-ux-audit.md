# Caffeine Tracker: Bedtime, newcomer persona audit

Persona: a first-time user who does not know the app's terminology and wants one useful result immediately.
Run: shift-audit-caffeine-newcomer-2-1792690256 (continues run 1, which committed `CaffeineUITests/NewcomerAuditUITests.swift`).

## Evidence
- Runtime: `gh-sim test --scheme CaffeineUITests --only CaffeineUITests/NewcomerAuditUITests` on GitHub run 39823455018 (Xcode 27.1, iPhone 17, iOS 27.0). Result: 3 passed, 0 failed (`test-summary.json`). 30 screenshots in `screenshots/`, tap target frame sizes in `tap-targets.txt`.
- I viewed the screenshots cited below. Motion and frame rate were NOT measured (not in scope here).
- Labels: RUNTIME means seen in a screenshot; SOURCE means read from code only.
- Test caveats (my test, not the app):
  1. The headless simulator never showed the system Apple Health sheet, so Health stayed "Not set up" for the whole run (confirmed in `20-settings-top`: "Saving to Health: Not set up"). Every log therefore took the local-only fallback. This is the "newcomer declines or never answers Health" path, a supported one, but it is not the granted-Health happy path.
  2. Tests 2 and 3 launched with onboarding already completed by test 1 (app state persisted), so `01-health-step-direct`, `01-large-welcome`, `02-large-bedtime` and `03-large-health` are the Now screen, not onboarding. They are still useful: they show Now at Accessibility XL. Onboarding at large text remains UNVERIFIED. A fix for the test is to add `-hasCompletedSetup NO` or uninstall between tests.

## Findings (most severe first)

### 1. Logged drinks do not count anywhere when Health is not connected (High, RUNTIME + SOURCE)
- Repro: finish onboarding without Health being granted (tap "Not now", or Health never answered), tap Drip coffee, tap "Log 95 mg".
- Observed (`13-now-after-log`, `15-now-scrolled`, `05-after-retry`): the banner says "1 entry is saved on this device only. They still count in every estimate here." while the card above it shows "0 mg estimated remaining now", "Nothing in the last 48 hours. Log a drink and this fills in.", AT BEDTIME "0 mg", "4-6h range 0-0 mg", and CONSUMED TODAY "0 mg". There is no "YOUR LOG" row either. After a second entry the banner reads "2 entries" and every number is still 0.
- Timeline (`17-timeline-7d`) also says "No caffeine recorded in this range" and 0 mg averages after logging.
- Cause (source): `HealthKitService.fetchHistory` builds history from `fetchSamples` only and never merges `pendingLocalSamples`, so the Timeline can never show a local-only entry. In `refreshCache`, `recentSamples = healthSamples + pendingLocalSamples` runs only if `fetchSamples` does not throw; the catch branch leaves `recentSamples` untouched and `lastError` is never displayed. `fetchSamples` swallows only `errorAuthorizationNotDetermined`; any other read error (for example authorization denied) skips the merge. I did not prove which error occurred in this run, so the Now-screen part of the cause is a hypothesis, the Timeline part is certain.
- Impact: a newcomer who skips Health sees the app discard their first drink and contradict itself in the same screen. This is the "one useful result immediately" test failing outright.
- Fix: always merge `pendingLocalSamples` into `recentSamples` (move the merge outside the do/catch or into a `defer`), include them in `fetchHistory`, show `lastError` when set, and add a unit test that a local-only sample raises `remainingNow`.

### 2. "Retry now" cannot help when Health was never connected, and gives no feedback (Medium, RUNTIME)
- `20-settings-top`: Settings shows "Saving to Health: Not set up", a "Connect Apple Health" button, and "Waiting to save 1" with "Retry now". The Now banner (`13-now-after-log`) offers only "Retry now", never "Connect Apple Health". Tapping Retry (`05-after-retry`) changes nothing visible.
- Impact: the banner's one action is a dead end for a user who skipped the prompt; the fix is two screens away in Settings.
- Fix: when `writeState == .notDetermined`, show "Connect Apple Health" in the banner (it already does this for `.denied` via Open Settings), and make Retry report "Still can't save" when it fails.

### 3. Welcome promises "one tap", the first log takes three taps (Medium, RUNTIME)
- `01-welcome`: "Log a drink in one tap", "One tap to log, one tap to undo". `11-now-empty` to `12-preview-sheet`: tapping Drip coffee opens a Drink preview sheet (title, drink picker, dose slider, date and time, WITHOUT/WITH DRINK, bedtime lines), then "Log 95 mg" is a second tap, i.e. tap, tap.
- Impact: false first promise; the sheet is a lot to take in for someone who only wanted to record a coffee.
- Fix: reword step 1 ("Tap a drink, see what it does to tonight, then log it") or offer a real one-tap log (long press or a plus on each chip). Keep the preview as the default if that is the product decision.

### 4. Onboarding is five steps before the first result, and two of them sell something a newcomer cannot use yet (Medium, RUNTIME)
- Steps: welcome, bedtime, Health, body data (`04-health-sheet` capture is actually this step), Caffeine+ (`10-plus-step`). The Now screen then opens at "0 mg".
- The body step ("Find the number your own nights react to", "personal cutoff", "9 measurements", "90 minutes after each dose") describes a feature that needs 21 nights (`CaffeineInsights.minimumCutoffNights`), and the Plus step lists "sleep, heart rate and HRV", "A half-life starting point for your body".
- Fix: first run = welcome, bedtime, Health. Offer body data from the Cutoff tab (it already has a connect card, `16-cutoff-tab`) and the Plus pitch after the first logged drink.

### 5. Preview sheet shows a past time in "good news" styling (Medium, RUNTIME)
- `12-preview-sheet` at 6:07 PM, bedtime 10:30 PM, dose 95 mg: WITH DRINK 52 mg, and a green clock-check line "Latest time this dose still lands under your preference: 12:52 PM".
- The preference is 25 mg, so this drink already exceeds it, but the line is green with a checkmark icon and the time is six hours ago. A newcomer reads green plus checkmark as "fine".
- Fix: when `latestTime < drinkTime` use the warning style and plain words ("This dose is already over your 25 mg preference at bedtime. It would have needed to be before 12:52 PM"). Icon and colour should follow the verdict, not just the presence of a value.
- File: `CaffeineViews.swift` forecastCard.

### 6. Jargon a first-time user cannot decode (Medium, RUNTIME)
- `11-now-empty`: "4-6h range 0-0 mg", "MODEL 5.0 hour half-life", "AT BEDTIME". `16-cutoff-tab`: "Stop guessing at the 5 hour average", "The half-life model is the same for everyone", "heart rate or HRV". Tab named "Cutoff" with title "Your Cutoff". `19-upgrade-tab`: "What sits under your cutoff", "A half-life starting point for your body". `12-preview-sheet`: "bedtime preference", "Reference range at bedtime". Welcome leads with "half-life model".
- Impact: nothing on Now says in one plain sentence what the big number means or what to do with it.
- Fix: one sentence under the bedtime figure ("How much may still be in your system at 10:30 PM"), spell out HRV once, explain half-life in the Today card as "about half clears every 5 hours", and show "0 mg" with an empty-state "Log a drink to see this" rather than "4-6h range 0-0 mg".

### 7. Small tap targets (Medium, RUNTIME, from `tap-targets.txt`, points)
| Control | Size | Where |
|---|---|---|
| Not now (Health step) | 59x18 | onboarding |
| Skip for now (body step) | 89x18 | onboarding |
| Continue with the free app | 189x18 | onboarding Plus step |
| Restore / Terms (onboarding) | 42x13 / 72x13 | footer |
| Undo | 38x18 | Now after logging |
| Refresh, Settings gear | 27x36, 31x36 | Now toolbar |
| Restore purchases (Upgrade) | 110x14 | paywall |
- All are below 44 points. The soft exits are the only way to decline a prompt and are 18 points tall; Undo is the only way to correct a mis-tap and is 38x18.
- Fix: give each a `.frame(minHeight: 44)` plus `.contentShape(Rectangle())`; for the soft exits make the row full width.

### 8. The free option on the Plus step is the weakest element on screen (Low to Medium, RUNTIME)
- `10-plus-step`: "Continue with the free app" is small grey text; "$29.99 per year" is the largest text, then a gradient "Continue with Caffeine+" button. The price-first order is required by the repo's 3.1.2 note, but the decline path is a tiny text link 18 points tall (finding 7).
- Fix: keep the billed amount, but make the free exit a full-width secondary button of equal height or place it beneath the legal row at 44 points.

### 9. Upgrade tab hero text is truncated (Low, RUNTIME)
- `19-upgrade-tab`: the subtitle ends "The cutoff itself, logging and both es..." (cut off by a line limit). The sentence carries the message that the cutoff is free. Allow it to wrap or shorten it.

### 10. Now at Accessibility XL: the floating tab bar covers content (Low, RUNTIME)
- `03-large-health` (which is Now at AX XL): the layout reflows without clipping text, but the banner's text runs behind the translucent tab bar, and ghost text of the card below shows through it in the normal-size shots too (`13-now-after-log`, `05-after-retry` bottom edge). Add a bottom content inset equal to the bar height.

### 11. Undo row can go stale or fail silently (Low, SOURCE only)
- `undoRow` compares `Date.now` to `lastLoggedAt + 120 s` only on re-render, so the row can outlive its window; `undoLast()` returns false when deletion fails and the button ignores the result. In the run, Undo worked and the row sat below the fold-adjacent area but was visible (`13-now-after-log`).
- Fix: clear on a timer and show an error on failure.

### 12. Deleting an entry is a long press (Low, SOURCE only)
- "YOUR LOG" offers delete only via `.contextMenu` (or the edit sheet). No swipe action, and the footer hint omits it. Note: no YOUR LOG row appeared in the run because of finding 1.

## What worked for this persona
- The empty Now card tells you what is missing instead of showing nothing.
- The Health step states plainly that declining is fine; the fallback banner is honest about where the entry lives (apart from finding 1).
- `30D` locked state (`18-timeline-30d-locked`) is clear: lock, reason, "See Caffeine+".
- Upgrade tab (`19-upgrade-tab`) fits one viewport with Restore, Terms and Privacy visible.
- Quick-add chips are large (117x83), the preview Log button is 366x50, onboarding primary buttons are 354x50 and in an identical frame on every step.
- Copy stays on the right side of the App Review rules ("may remain", "estimate", "preference").

## Priority order
1. Finding 1 (data loss illusion; small code fix, add a test).
2. Finding 2 (banner action when Health not connected).
3. Findings 3 and 6 (copy, cheap).
4. Finding 5 (wrong signal colour).
5. Finding 7 (tap targets).
6. Finding 4 (shorten first run), then the rest.
