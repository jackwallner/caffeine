# Protein Tracker super-audit

Audit date: 2026-08-06

Build reviewed: `1.0.0 (5)`

Scope: user-facing behavior, layout, content, accessibility, state handling,
conversion surfaces, HealthKit failure states, watch and widget code paths, and
the product promise in the project guide. No application code was changed for
this audit.

## Executive triage

The core product is clear and focused. The allowed-HealthKit phone flow works,
the main number is easy to understand, logging and undo work, source exclusion
changes the total correctly, history is mathematically consistent, dark mode is
coherent, and the paywall has a credible three-plan presentation.

The most important issues to fix before relying on real users are:

1. A user who denies HealthKit read access is shown `Reading protein Connected`
   and loses the prominent Today recovery card. The app has no honest read
   permission state, and the user can believe importing is working when it is
   not.
2. The write-denied local fallback updates the hero and history, but Today and
   Sources say that nothing was logged. This directly contradicts the data the
   user just entered.
3. Inactive tabs remain exposed to accessibility and automation. Runtime
   snapshots of Today exposed Settings controls, and tapping a stale blank
   switch activated the wrong Settings control or opened an offer sheet.
4. The onboarding trial price visually collides with the last selling-point row
   on the iPhone screenshot width. The billed amount needs a clean, isolated
   block.
5. Enabling the evening reminder schedules it with `total: 0`, so the first
   notification can report the full target even when the user has already eaten
   or finished for the day. Notification permission denial also leaves the
   feature looking enabled.
6. Circular widgets and the circular/corner watch complication display zero
   when the user is over target instead of displaying the overage.
7. The target sliders and feedback editor are not named correctly for assistive
   technology. The target slider was observed with a null accessibility label.
8. The floating bottom tab capsule can cover the last history row and lower
   Settings content at the end of a scroll.

There are no confirmed P0 crashes or data-loss events in the exercised phone
flows. There are several P1 trust, accessibility, and feature-state issues that
should be treated as release blockers for the affected paths.

Severity used below:

- P0: data loss, security issue, or unusable primary flow.
- P1: release-blocking correctness, trust, accessibility, or monetization issue.
- P2: meaningful usability, content, layout, or edge-state issue.
- P3: polish, copy, or low-risk improvement.

## Evidence and method

### Runtime surfaces exercised

- Fresh iPhone install and onboarding from the welcome screen through the free
  exit.
- HealthKit authorization allowed and denied paths.
- Muscle, GLP-1, and post-bariatric reason choices, plus the general option by
  source inspection.
- Onboarding target slider and Settings target slider.
- Free Today with no data, locked quick add, locked Other amount, and locked
  source/history/reminder entry points.
- Protein+ Today with seeded multi-source data, actual HealthKit-simulator
  entries, undo, custom gram picker, source exclusion, and over-target totals.
- Sources with no rows, one own source, and an external source that is toggled
  off and back on.
- Free seven-day history, seeded thirty-day history, empty history, local-only
  fallback history, and the bottom of the long list.
- Settings from top to bottom, Apple Health statuses, target/reason picker,
  quick-add steppers, Protein+ state, reminder row, restore, appearance, support,
  legal links, and dark mode.
- Trial offer sheet, full paywall, lifetime/yearly/monthly selection, review
  enjoyment prompt, review pitch, feedback form, and mailto return behavior.
- App Store style iPhone screenshots in light and dark appearance.
- Generic watch target build and source-level watch/widget/complication review.

### Headless devices

- iPhone 17 Pro, iOS 26.5, pool group 1, UDID
  `2C7A80C1-1228-411A-B9AD-A7DEED683F79`. This was the primary layout device.
- Paired iPhone 17 Pro, iOS 26.3.1, pool group 9, UDID
  `ACCA6797-0070-4807-B21D-4F930237B574`, used for fresh permission denial and
  local fallback.
- Paired Apple Watch SE 3 44 mm, watchOS 26.2, UDID
  `010BAC4F-9C8E-4404-AC60-3F575D18973E`. The watch target built successfully
  for the generic watch simulator SDK, but Xcode destination matching and
  `simctl` rejected this watch UDID while it was checked out. The other paired
  watch group was owned by another agent and was not touched. Watch runtime
  screenshots and tap behavior therefore remain an explicit verification gap.
- No `Simulator.app` window was opened. All runtime work used headless
  XcodeBuildMCP, `simctl`, and accessibility tooling.

### Deliberate audit limitations

- A real device was not used. HealthKit read/write behavior with MacroFactor,
  Cronometer, MyFitnessPal, or another food logger is not verified here.
- A real App Store or RevenueCat purchase was not made. Simulator StoreKit
  products and the local `-DemoPro` path were used for layout and Pro behavior.
  The simulator purchase method is intentionally disabled by
  `StoreService`, so a successful purchase cannot be inferred from this audit.
- iOS widgets and watch complications were built and inspected from their
  WidgetKit source, but were not placed on a SpringBoard or watch face in the
  headless pool. Their visual and interactive installation flow needs a device
  pass.
- Dynamic Type, VoiceOver focus navigation, Reduce Motion, right-to-left text,
  and localized prices were not exhaustively rendered. Accessibility tree
  inspection was performed throughout and already found concrete failures.

## Persona matrix

| Persona | Primary path | Result | Main concern |
| --- | --- | --- | --- |
| New privacy-conscious user | Welcome, permission, free exit | Clear value proposition and no-account promise | HealthKit copy says `Protein` in the system sheet but `Protein Tracker` in the explanation; denial state is misleading |
| Lifter | Muscle reason, target, phone logging | Smooth, focused, target is editable | Suggested target language can still sound prescriptive; target slider has no accessible name |
| GLP-1 user | GLP-1 reason, target, upgrade | Personalized copy is respectful and target remains editable | `A common starting point while appetite is suppressed` is close to medical guidance; no adjacent disclaimer on the onboarding target page |
| Post-bariatric user | Bariatric reason, target, free exit | Explicitly tells user to use clinic number | Hard-coded 70 g fallback can look like an app-assigned medical target; the page does not visibly repeat the disclaimer |
| General health user | General reason, target, free exit | Simple and non-judgmental | `Sensible` starting number is still an app suggestion without context about where it comes from |
| Free Apple Health reader | Existing data, free Today/history/widget | Read-only promise is understandable; free history is useful | External import depends on HealthKit reads that were not verified with real food loggers |
| Free user who declines HealthKit | Deny system sheet, complete setup | App still completes setup | Read status falsely says connected, Today lacks a Connect card, and Sources has no recovery action beyond refresh |
| Protein+ phone logger | Quick add, Other, undo, sources | Fast logging works; source selection recalculates totals | Local fallback is absent from source provenance; reminder can schedule the wrong amount |
| Watch-first Protein+ user | Watch presets, Other, undo | Source code is intentionally compact and above-fold oriented | Watch runtime was not installable on the checked-out 26.2 destination; over-target circular complication code is incorrect |
| Multi-source food logger | Sources, duplicate-risk warning, exclusion | External source toggle correctly changes total and remains visible as excluded | Wording says apps are writing now when the data proves only recent samples |
| User with no data | Empty Today, empty Sources, empty History | Empty surfaces are visually calm | Multiple versions of “nothing logged” can conflict with local fallback and explicit zero rows |
| User over target | Actual entries past target | Phone hero clearly says `25 grams over` and `185 / 160 g` | Circular widget and some complications reduce the result to zero |
| Accessibility user | Snapshot tree, controls, feedback | Hero and quick-add buttons have some useful labels | Hidden tabs leak controls, sliders are unnamed, reminder switch and feedback editor have blank labels |
| Dark-mode user | Today, History, Settings, paywall | Palette remains readable and coherent | Bottom overlay and tiny legal text remain issues in dark mode too |
| User without Mail configured | Review feedback, send | Feedback sheet displays correctly | `mailto:` open returns silently and the sheet closes without confirming delivery |

## Screen-by-screen audit

## 1. Onboarding

### Welcome

What works:

- The first screen communicates the product in one sentence: `Grams left, all
  day`.
- The anti-feature statement is strong and differentiated: no calorie counting,
  food database, or photo guessing.
- The three benefit cards establish the watch-first, Apple Health, and local
  data model before asking for permission.
- `Stays on your device. No account.` is a useful trust line and is not buried
  in legal copy.
- Restore, Terms, and Privacy are reachable before setup is complete.
- The layout was clean on the iPhone 17 Pro portrait viewport with no clipping.

Watch-outs:

- The visible brand in the app and metadata is `Protein Tracker`, while the
  system permission sheet labels the app `Protein`. The difference is visible
  at the moment the user is deciding whether to share health data. See F-007.
- Continue launches an asynchronous HealthKit request and moves the app to the
  reason page immediately. This is acceptable when the system sheet is fast,
  but the app has no visible loading or permission-pending state if the sheet
  takes time.
- The welcome copy says data stays on-device. That is directionally honest, but
  HealthKit and Apple system services are involved, and a user could read it as
  a promise that no Apple Health synchronization occurs. Consider making the
  local-storage meaning explicit in later copy.

### HealthKit permission sheet

Observed allowed path:

- Apple presents one combined read/write sheet, which is better than two
  prompts.
- The explanation correctly says Protein Tracker saves the grams added in the
  app and keeps them locally if writes are declined.
- The system permission sheet initially disables Allow until the user enables a
  category, which is Apple behavior and not an app defect.

Observed denied path:

- Tapping `Don’t Allow` produces the expected Apple follow-up alert that health
  categories can be enabled later in Health.
- After dismissing it, the user can finish onboarding instead of being trapped.
- The app does not surface the denial as a setup failure, which is good for a
  read-only/free product, but it then misstates the resulting read state. See
  F-001.

### Reason selection

What works:

- Four options are visible without a wizard branching into separate products.
- Selection is obvious with an orange outline and checkmark.
- The copy for bariatric surgery explicitly defers to the clinic target.
- The reason is presented as a starting-number choice, not a different feature
  set, which supports the single-product positioning.

Concerns:

- The syringe icon and medication-specific copy make this a medical-adjacent
  surface. The copy avoids prohibited treat, cure, diagnose, and prescribe
  claims, but the surrounding target suggestions need the same caution.
- A user can move from reason selection to target without any reminder that the
  number is not medical advice. The disclaimer appears later in Settings, not
  on this high-risk onboarding branch.

### Target selection

What works:

- The number is visually dominant and the unit is always present.
- The range is broad enough for manual entry through the slider and uses 5 g
  steps.
- Changing the reason re-anchors the suggestion until the user moves the
  slider. This is a reasonable model and avoids overwriting an explicit choice.
- The copy for bariatric users says to enter the clinic-provided number.

Problems:

- Runtime accessibility inspection found the onboarding `Slider` with a null
  accessibility label. The visible number does not replace a semantic label
  such as `Daily protein target, 70 grams` and an adjustable value. See F-004.
- The target page shows fallback suggestions such as 150 g for strength, 100 g
  for GLP-1, and 70 g for bariatric users. These are visually presented as
  established starting values, which may be read as the app setting a medical
  target even though the prose says otherwise. See F-012.
- `HealthKitService` contains body-mass authorization code, but onboarding only
  calls the body-mass fetch and never calls the explicit body-mass authorization
  request. On a fresh install, a body weight already present in Health may not
  be readable, so the UI usually falls back to the hard-coded reason value. The
  Info.plist says body weight is read if the user asks for a suggestion, but the
  user is never asked in this flow. See F-013.
- The target page has no quick numeric entry for a precise value. A user who
  needs 73 g must drag a slider through many steps and cannot type the number.
  This is more significant for users whose clinician gave an exact target.

### Trial offer step

What works:

- Free versus Protein+ is explained in plain language. The free number, widget,
  and complication stay visible, while logging, presets, sources, reminder,
  and longer history are paid.
- `Get Started` is a clear soft exit and does not force a purchase.
- Restore, Terms, Privacy, billed amount, trial note, and cancellation language
  are present.
- The app uses a neutral CTA instead of hiding the price behind a trial button.

Observed layout issue:

- On the iPhone 17 Pro screenshot width, the `$14.99 per year` billed amount
  visually sits too close to, and appears horizontally entangled with, the
  `Source control` selling-point detail. The price does not read as a separate
  isolated purchase block. This is the most serious onboarding layout issue
  because price clarity and trust are involved. See F-005.
- The legal footer and disclosure are small and low contrast. They are present,
  but users are likely to skip them, especially in dark mode or with reduced
  visual acuity.
- On the simulator, `Continue with Protein+` intentionally does not purchase.
  It returns to the same state with no error because RevenueCat is not
  configured in simulator builds. This is an audit limitation for purchase, but
  the real-device failure and loading states still need a sandbox purchase pass.

## 2. Today

### Free empty state

What works:

- The hero answers the product question immediately: grams left, consumed versus
  target, and a progress ring.
- Locked buttons remain visible, so the user understands what Protein+ adds.
- The free user still sees the total surface and can keep the widget and watch
  complication, consistent with the product promise.
- The source card is compact and discoverable.

Concerns:

- When HealthKit read access is denied, the Today screen did not show the
  intended `Connect Apple Health` card. The screen instead looked like a normal
  empty day. See F-001.
- In free mode, tapping a preset opens a personalized offer sheet. This is a
  sensible conversion point, but it interrupts the immediate feedback loop. The
  sheet should preserve the exact context and ensure dismissal returns to the
  same scroll position, which worked in the exercised pass.
- The empty source card and the history empty card use different versions of
  “nothing logged.” A new user can interpret the app as not having loaded data,
  as having a valid zero, or as requiring a paid upgrade.

### Protein+ logging

What works:

- Quick-add buttons are large, distinct, and easy to hit.
- The custom amount sheet uses 5 g increments from 5 to 200 g, avoiding a
  keyboard and preserving the grams-only interaction model.
- Undo appears immediately after a log and disappears after the eight-second
  window. Actual HealthKit entries were removed successfully within the window.
- The over-target state was clear in the phone app: `25 grams over`, a full ring,
  and `185 / 160 g eaten today`.
- Repeated entries accumulate correctly, and the source row updates with the
  current total and freshness.

Concerns:

- Undo is intentionally session-scoped and has no later edit path. After eight
  seconds, a mistaken tap cannot be corrected from the app. This is consistent
  with the stated product model, but it is a meaningful risk for a one-tap
  logger and should be an explicit product decision.
- The custom wheel was visible and usable, but its semantic accessibility
  exposure was not complete in the runtime snapshot. Verify that VoiceOver can
  identify the selected grams and adjust it without relying on a visual wheel.
- The local fallback path is not represented in the source card or Sources
  screen. See F-002.

### Write-denied fallback

This was tested after denying HealthKit and enabling the local Pro override only
for the simulator audit.

Observed sequence:

1. Today showed `0 / 150 g` and the locked free state before the local override.
2. After a 25 g entry, the hero changed to `125 grams left` and `25 / 150 g`.
3. The UI showed `Added 25 g` and `Saved on this device only` with a clear
   explanation that Apple Health is not allowing writes.
4. History correctly showed 25 g for the current day and a 4 g seven-day
   average.
5. The Today source card still said `Nothing logged yet today`.
6. Sources opened to `No protein logged today` and had no local own-app row.

The fallback itself is valuable and the data total is correct. The provenance
surfaces are wrong. A user can see 25 g in the hero and history while being told
that no protein was logged. This is a direct release blocker for the fallback
path. See F-002.

## 3. Sources

### Empty state

What works:

- The explanation correctly teaches that the screen only sees apps that write
  `dietaryProtein` to Apple Health.
- It warns that not every food logger writes the type and tells the user that
  Protein Tracker can become the source when adding grams.
- Refresh and last-checked controls are visible.

Problems:

- Local-only entries are omitted even though they are counted in the same day
  total. The empty state is therefore false after a write-denied log. See F-002.
- When HealthKit read access is denied, the screen offers refresh but does not
  offer the more useful recovery path to the Health settings state. Settings
  contains the relevant navigation, but this screen is the one a user opens to
  understand missing data.

### Populated state and duplicate risk

What works:

- The own source appears first and is marked `THIS APP`.
- External sources show grams and freshness, which is the right information for
  resolving duplicate logging.
- An external toggle can be switched off, and the Today total immediately
  recalculates. The excluded row remains visible but becomes visually muted,
  which is useful confirmation.
- The duplicate warning is direct without claiming certainty about which meal
  is duplicated.

Concerns:

- `Writing protein today` and `Every app writing dietary protein counts by
  default` imply ongoing writer activity. The query actually proves that a
  source produced samples in the day window. The freshness value softens this,
  but `Contributing sources today` would be more precise.
- If the user excludes an external source and then the source stops appearing in
  a later day, the stored exclusion is invisible. This is intentional opt-out
  behavior, but there is no list of remembered exclusions to help users undo an
  old choice.
- Sources are a core differentiator but are only a Protein+ feature. A free user
  can see the source icon and open the sheet, then encounters a locked switch or
  an offer. The conversion is understandable, but the empty state is not
  useful to a free user who is trying to diagnose HealthKit import.

## 4. History

### Free seven-day history

What works:

- The summary gives target-hit count and average at a glance.
- The chart has a visible target rule and uses color to distinguish days that
  reached the target.
- The daily rows are easy to scan and include explicit dates and grams.
- The free limit is stated by the locked thirty-day card instead of hiding the
  feature.

Problems:

- With no data, the chart says `Nothing logged yet. Days appear here as protein
  lands in Apple Health` while the list below renders seven explicit 0 g rows.
  This is technically consistent but semantically redundant. The user has to
  decide whether the zeros are real data or placeholders. See F-010.
- After the denied-write fallback, History correctly included the local entry.
  This makes the contradiction with Today and Sources more noticeable.
- A new user with one large day and six zero days sees a low daily average. The
  value is mathematically correct, but the screen does not say whether the
  denominator is all calendar days or only days with data. Consider labeling it
  `average per day in this window`.

### Protein+ thirty-day history

What works:

- Seeded data rendered a clear thirty-day graph, target line, daily rows, hit
  count, and average.
- The longer window is a real value difference from free, not merely a disabled
  button.
- The graph remains readable in dark mode.

Overlay issue:

- At the bottom of the thirty-day list, the final row was partially hidden
  beneath the floating tab capsule. The same fixed capsule can cover lower
  Settings content. The user can infer that a row exists, but cannot read it
  comfortably or confirm its state. See F-009.

## 5. Settings

Settings is complete in breadth, but it is the most crowded surface and the
most affected by the persistent tab overlay and accessibility state.

### Apple Health

What works:

- Separate read and write statuses are useful when they are accurate.
- Refresh, Open Apple Health, and the permission-navigation footer are practical.
- The write-denied explanatory text correctly tells the user that local entries
  are retained and later migrated.

Problems:

- The read status is not an actual read authorization result. After the user
  denied the HealthKit sheet, Settings showed `Reading protein Connected` in
  green. Apple does not expose the read answer directly, but the product should
  avoid presenting “connected” as a verified fact when the sample query is
  empty. See F-001.
- The long footer is useful but dense. It combines Health privacy navigation,
  read/write troubleshooting, and migration behavior in one paragraph. A
  shorter status-specific explanation would be easier to scan.
- The Health section does not show the number of samples or the last successful
  read, even though the Sources screen has a last-checked timestamp. Cross-link
  these states or expose one consistent freshness indicator.

### Target and reason

What works:

- The target is visible with units and can be adjusted in 5 g steps.
- The reason is editable after onboarding and the rationale updates.
- The footer contains the non-diagnostic disclaimer.

Problems:

- The Settings slider is not given a clear accessibility name/value in code or
  runtime inspection. See F-004.
- The GLP-1 rationale says `A common starting point while appetite is
  suppressed`, which can sound like a clinical recommendation. See F-012.
- The target footer is long enough that the disclaimer is easy to miss below the
  control. The user should not have to read a paragraph to understand authority
  over the number.

### Quick add

What works:

- Pro steppers changed values correctly, and the changed phone preset was
  reflected on Today.
- The footer explains that the same three values appear on the Watch.
- Free rows remain visible with locks, which communicates the upgrade boundary.

Problems:

- The visible stepper has a duplicate amount label in the runtime accessibility
  tree because the Stepper label and the trailing amount are both rendered. The
  accessible result should announce one control with one value and clear
  increment/decrement actions.
- At the bottom of the Settings scroll, the tab capsule overlays the support
  and About area. See F-009.

### Protein+ and reminder

What works:

- Active versus locked Protein+ is visually clear.
- Restore Purchases is always available.
- The reminder row explains the benefit in terms of exact grams left.
- The free state shows the feature and a lock rather than pretending the toggle
  is usable.

Problems:

- The locked reminder is represented as a switch, but the runtime accessibility
  tree frequently exposed it as a blank switch. A user relying on VoiceOver may
  not know what the switch controls. See F-003 and F-018.
- Enabling the reminder writes `reminderEnabled = true` before the notification
  authorization result is known. If the user denies notifications, the row can
  remain enabled even though no notification will arrive.
- The Settings binding calls `scheduleReminder` with `total: 0`. It can therefore
  schedule a notification with the wrong remaining grams, including after the
  user has already met the target. See F-006.
- The reminder is described as a single evening nudge, but there is no visible
  indication of the exact scheduled time until Pro is active and the row is
  enabled. The time picker itself was not runtime-exercised because the blank
  switch target was not reliable.

### Appearance, support, and About

What works:

- System, Light, and Dark options work and remain consistent across Today,
  History, and Settings.
- Privacy Policy, Terms of Use, version, rate, and feedback are easy to find
  after scrolling.
- The disclaimer in About is clear and avoids treatment claims.

Problems:

- The persistent tab capsule overlays the lower support/footer content at the
  end of the scroll.
- `Rate Protein Tracker` and `Send feedback` are orange on light and dark
  surfaces, but the support footer is small and low contrast.
- The review copy repeats the product positioning as `a protein tracker that is
  only a protein tracker`, which sounds awkward. See F-022.
- The DEBUG `Local Pro override` switch appears in the runtime build used for
  this audit. It is correctly conditional on DEBUG and should not ship, but
  screenshot/test configurations should be clearly distinguished from a
  production build when reviewing captures.

## 6. Trial offer and paywall

### Personalized offer sheet

What works:

- The sheet uses the feature the user just tried to access as the headline.
- It presents the billed amount and the trial disclosure close to the primary
  CTA.
- Not now, Terms, Privacy, and the purchase path are present.
- The sheet dismisses cleanly back to the underlying screen.

Problems:

- Terms and Privacy are small in the compact sheet, especially in dark mode.
- The sheet is visually dense when the feature detail lines wrap. Test at
  smaller phones, larger text sizes, and languages with longer prices.
- As with onboarding, simulator purchase is intentionally a no-op. The real
  device must confirm loading, cancellation, purchase, pending, restore, and
  entitlement propagation to the phone, widget, and Watch.

### Full paywall

What works:

- The hero and feature list are focused and not overstuffed.
- Lifetime, Yearly, and Monthly cards are distinct and selectable.
- Yearly defaults selected and shows the 7-day trial, annual price, and savings.
- Selecting lifetime changes both the CTA to `Unlock Lifetime` and the
  disclosure to `One-time purchase. Lifetime access, no subscription.`
- Selecting monthly changes the disclosure to the recurring monthly terms.
- Restore, Terms, Privacy, and close are accessible targets with useful labels.
- The close button is correctly exposed as `Close` in the runtime snapshot.

Problems:

- The lifetime card itself only shows `$29.99` until it is selected. A user can
  read the card without seeing `one-time purchase`, while the subscription
  cards have more explicit cadence language. Put the purchase type directly on
  the lifetime card.
- Legal disclosure and footer links are tiny at the bottom. They are present but
  not comfortably readable in the screenshot and dark appearance.
- The paywall uses a fixed footer slot to prevent CTA jumps, but the amount of
  text in that slot is substantial. Test longer localized prices, failed
  product loading, and used-trial copy at the smallest supported phone.
- The debug fixture correctly renders products without configuring the
  production RevenueCat key. Do not use the fixture as evidence of a real
  transaction.

## 7. Review and feedback funnel

### Review enjoyment prompt

What works:

- The sheet is compact, friendly, and gives the user a direct negative path.
- `Yes, it's helping`, `Not really`, and `Not now` are clear choices.
- The review pitch is separate from the initial enjoyment question, which is a
  respectful funnel.

Problem:

- Settings can invoke the enjoyment prompt manually and intentionally bypass
  passive eligibility. The copy still says `You have hit your protein target a
  few days running.` During the audit the app had only one observed hit on the
  active simulator, yet the manual prompt made that claim. The user can see a
  statement that is not true for their account. See F-016.

### Review pitch

What works:

- The pitch explains the indie-developer context without hiding the “Maybe
  later” path.
- The App Store CTA is explicit and the URL is opened only after the user
  chooses it.

Polish:

- The phrase `a protein tracker that is only a protein tracker` is repetitive
  and less natural than the rest of the product voice.
- The actual App Store transition was not validated in the simulator, so verify
  that returning from the store leaves the app in a stable state and that the
  prompt is not immediately re-presented.

### Feedback form

What works:

- The form is private, account-free, and does not require analytics consent.
- The send button is disabled until text exists.
- The typed text was accepted and the button enabled.

Problems:

- Runtime accessibility exposed the editor as a `text-field` with an empty
  label. The visible prompt above it is not programmatically associated. See
  F-018.
- `UIApplication.shared.open(mailto:)` is called without checking the completion
  result. On the headless simulator, the sheet closed and returned to Settings
  without a Mail composer or an error. A user without a configured Mail client
  can lose the feedback context and receive no explanation. See F-017.
- The form uses a large blank editor on the full sheet. It has adequate space,
  but the initial focus and keyboard behavior should be tested on a real phone,
  including whether the Send button remains visible above the keyboard.

## 8. What's New

Source review found a one-time sheet that correctly separates update awareness
from purchase state:

- It explains that the free total, widget, and complication remain.
- It highlights wrist logging, quick presets, and source control.
- A Pro user gets Open Settings; a free user gets Explore Protein+.
- Fresh installs are seeded past the What's New version so the sheet does not
  interrupt onboarding.

The normal update-triggered presentation was not reliably reproducible after
manually editing the simulator App Group preference. The app rewrote the
version marker during launch. Verify the update migration path on a real
upgrade from the previous build, including a user who dismissed the prior
announcement and a user who is already Pro.

## 9. Apple Watch app

### Intended watch experience from source review

The watch app is deliberately one screen:

- Hero ring, grams left or grams over, and a consumed/target pair.
- Three large preset buttons.
- `Other` opens a Digital Crown gram picker.
- After a log, Undo replaces the Other slot for eight seconds rather than
  adding a fourth row.
- Free users see a locked wrist-logging notice while their total and
  complication remain available.
- There is no navigation title, which protects the 41 mm above-fold budget.
- Settings, target, presets, Pro status, and setup completion travel from phone
  to watch through WatchConnectivity. Entries intentionally travel through
  HealthKit rather than a separate write queue.

These are good product decisions for a wrist-first app. The three-button layout
is simple and the no-queue architecture is consistent with the stated source of
truth.

### Watch-specific audit risks

- The requested 41 mm above-fold behavior was not captured because the checked
  out 44 mm watch runtime could not be addressed by Xcode/simctl. The target
  built for the generic watch simulator SDK, but launch/install verification is
  still required on a compatible paired runtime.
- The circular watch complication displays `entry.remaining` directly. When
  total exceeds target, remaining is zero, so the circular complication can show
  zero even though the phone hero and rectangular/inline formats know the user
  is over. The corner complication has the same issue. See F-020.
- `WatchGramPicker` exposes a focused Digital Crown value but does not provide
  an explicit accessibility label or hint for the selected amount. Verify
  VoiceOver and Crown adjustment on hardware.
- The watch app's local App Group cache and HealthKit refresh need a paired-device
  test after a phone log, watch log, phone asleep, and a reconnect. Source code
  is consistent with the intended architecture, but this is not proven by the
  generic build.
- Verify the free lock state after a new phone install before setup completion,
  after setup completion without Pro, and after a Pro purchase on the phone.

## 10. iOS widget and watch complication

### iOS widget source review

Supported families are small, medium, circular accessory, rectangular
accessory, and inline accessory. The provider reads the App Group SwiftData
cache and reloads from HealthKit reconciliation, which is the correct WidgetKit
architecture.

What works in the implementation:

- Small and medium families use over-target copy when over the target.
- Rectangular and inline families use centralized formatting helpers.
- Accessibility combines the small widget into a `Protein: ...` label.
- The timeline has an hourly fallback and the app requests reloads after cache
  writes.

Defect:

- The iOS `accessoryCircular` family uses `entry.remaining` as its current value
  label. It does not switch to `entry.overage` when over target. The user gets a
  zero instead of a positive result on one of the most prominent widget sizes.
  See F-020.

### Watch complication source review

What works:

- Circular, rectangular, inline, and corner families are supported.
- Rectangular and inline formats use `remainingHeadline` and
  `compactRemaining`, which include over-target language.
- The complication intentionally remains available to free users.

Defects:

- Circular uses `entry.remaining`, which becomes zero over target.
- Corner uses `entry.remaining`, which also becomes zero over target.
- There is no visible widget-specific distinction between a true zero remaining
  state and an over-target state in those families.

The widget and complication surface should be treated as first-class product
screens, not only as build artifacts. Add a real-device or compatible simulator
matrix for empty, under-target, exact-target, and over-target snapshots.

## 11. System, legal, and cross-cutting review

### HealthKit copy and identity

- The app name is `Protein` in `CFBundleDisplayName` and in the Apple Health
  permission sheet.
- User-facing explanatory text, App Store metadata, and Settings use `Protein
  Tracker`.
- The explanation itself is clear, but the identity mismatch is visible on the
  most sensitive permission surface. See F-007.
- The iOS and watch Info.plists contain read/write usage descriptions and the
  entitlements include HealthKit, background delivery, and the App Group.

### Privacy and no-account promise

- The app does not show an account or sign-in flow.
- Feedback uses a private mail draft rather than an in-app analytics form.
- The HealthKit description explains source selection and local write fallback.
- Verify the production privacy policy against the actual use of RevenueCat,
  StoreKit, HealthKit, notifications, and mailto feedback before submission.

### Orientation and device assumptions

- The phone app is portrait-only in the Info.plist and was visually checked on
  the iPhone 17 Pro portrait viewport.
- iPad was not exercised. The project has an iPad simulator in the shared pool,
  but the metadata and target settings should make the intended iPhone-only
  behavior explicit if iPad is not supported.
- Larger text and compact phones were not exhaustively tested. The onboarding
  trial page and paywall are the first surfaces to recheck because they have
  fixed footer slots and dense copy.

## Findings register

### F-001, P1, HealthKit read denial is reported as connected

Evidence: on a fresh install, the Health Access sheet was denied. After setup,
Today showed no Connect Apple Health card. Settings showed `Reading protein
Connected` in green and `Saving to Health Off` in red. The app source sets
`isAuthorized = true` once the permission request completes, even though Apple
does not reveal the read authorization answer.

Impact: a user who declined read access can think the import is healthy, cannot
find a prominent recovery action on Today, and sees an empty source list without
an explanation.

Requested remediation: separate “permission sheet answered,” “read data
available,” and “write allowed.” Do not label read as Connected unless there is
positive evidence. Show a recovery card on Today and Sources when the read
result is empty or unavailable, with a route to Apple Health settings.

### F-002, P1, local write fallback contradicts Today and Sources

Evidence: after write denial, adding 25 g changed the hero to 25 g eaten and
history to 25 g, and showed the fallback banner. Today still said `Nothing
logged yet today`; Sources said `No protein logged today` and had no own-app
row.

Impact: the primary total and provenance screens disagree immediately after a
successful user action. This undermines the explicit promise that denied writes
are retained locally.

Requested remediation: represent local-only entries in the own-source row or a
separate `On this device` row, include them in the Today source summary, and
label whether the grams are pending migration to Health. Ensure the empty state
only appears when both HealthKit samples and local entries are absent.

### F-003, P1, inactive tabs leak accessibility controls

Evidence: the root keeps Today, History, and Settings NavigationStacks alive in
a ZStack. Runtime snapshots while Today was active included Settings controls
such as Restore Purchases, Theme, Local Pro override, Rate Protein Tracker, and
Privacy. While Settings was active, the tree often exposed only the tab buttons
and omitted the visible Settings content. A blank switch ref could activate the
wrong Settings switch or open a purchase sheet.

Impact: VoiceOver users can encounter invisible controls, automation can tap a
control from the wrong screen, and assistive focus order does not match the
visual screen.

Requested remediation: make inactive tab content inaccessible at the host
level, or mount only the selected tab. Verify with a complete accessibility
tree while each tab is selected, including sheets and scroll positions. Do not
rely on the current nested `.accessibilityHidden` modifier alone.

### F-004, P1, target sliders have no accessible semantic label

Evidence: the onboarding target slider appeared in accessibility inspection as
a Slider with a null AX label. The visible number changed visually, but the
accessibility element did not communicate that it was the daily protein target
or expose a useful value description. Settings uses a similarly bare Slider.

Impact: a VoiceOver user cannot reliably find or adjust the most important user
setting. The issue is more serious for users entering a clinician-provided
number.

Requested remediation: add a descriptive accessibility label, current gram
value, adjustable actions, and a clear minimum/maximum hint. Verify on both
onboarding and Settings at small and large text sizes.

### F-005, P1, onboarding price block collides with selling-point content

Evidence: on the iPhone 17 Pro viewport, `$14.99 per year` appeared adjacent to
or visually entangled with the final `Source control` detail rather than as a
separate price block. The price was not immediately scannable as a commitment.

Impact: purchase clarity and App Review price presentation are weakened at the
first conversion decision.

Requested remediation: give the billed amount its own vertical block with a
minimum width and spacing. Test 320, 375, 402, and larger text sizes, and check
the trial disclosure and footer at every height.

### F-006, P1, reminder schedules with total zero and ignores denial

Evidence: `SettingsView` calls `NotificationService.scheduleReminder` with
`total: 0`. The notification service uses that total to build the body and to
decide whether the target is already met. The Settings binding also sets the
reminder enabled before it knows whether notification authorization succeeded.

Impact: the notification can say the user has the full target remaining after
they have eaten or completed it. If notifications are denied, the UI can look
enabled while delivering nothing.

Requested remediation: schedule from the current reconciled total, reschedule
on refresh and settings changes, and only persist the enabled state after
authorization is granted. Surface a clear `Notifications Off` state with a
route to Settings when the user denies or later revokes permission.

### F-007, P2, permission identity says Protein while the product says Protein Tracker

Evidence: the Apple Health system sheet displayed `Protein` as the app name,
while the explanation, Settings, and App Store product use `Protein Tracker`.
The app and watch Info.plists set the display name to `Protein`.

Impact: users may wonder whether the permission belongs to the app they just
opened. This is a trust issue at the most sensitive point in onboarding.

Requested remediation: choose one public product identity and align the display
name, HealthKit copy, settings navigation, watch label, and marketing assets.

### F-008, P2, denied read state has no Today recovery path

Evidence: this is the user-facing portion of F-001. After denial and setup,
Today showed only the empty source card and locked features, with no Connect
button. Settings had the recovery controls, but it required navigating away and
scrolling.

Impact: a user who made a reasonable privacy choice cannot discover how to
change it from the screen that shows missing data.

Requested remediation: add a visible read-access recovery card or a source empty
state action. Keep the free user in the product instead of making HealthKit
troubleshooting a scavenger hunt.

### F-009, P2, floating tab capsule occludes scroll content

Evidence: the final row of seeded thirty-day History was partially hidden under
the fixed bottom capsule. Lower Settings content and support text were also
visually under the capsule at end-of-scroll positions. The root ignores the
bottom safe area and the scroll content only reserves 24 points of bottom
padding.

Impact: users cannot read or confirm the final content, especially in a long
history list or with larger text.

Requested remediation: reserve the actual tab capsule height plus safe-area
inset inside each scroll view. Verify the last row, last Settings section, and
sheet dismissal at all supported phone heights.

### F-010, P2, empty History repeats an ambiguous zero state

Evidence: the chart card says `Nothing logged yet` while seven daily rows below
show explicit `0 g` values.

Impact: the user cannot tell whether the rows are loaded zeros, placeholders, or
an absence of permission/data.

Requested remediation: use one primary empty-state explanation and label rows as
calendar days if they remain visible. Distinguish “no samples available” from
“verified zero grams.”

### F-011, P2, over-target ring semantics are visually busy

Evidence: the phone over-target state showed a full orange ring plus a green
secondary arc. The text correctly said `25 grams over` and `185 / 160 g eaten
today`.

Impact: the copy is clear, but the two arcs can be read as two separate progress
measures or as a second target. This is a comprehension risk on a product whose
promise is one number.

Requested remediation: confirm the green arc meaning with a quick user test. If
users do not immediately read it as overage, use a simpler over-target visual
state or a legend/accessibility description.

### F-012, P2, medical-adjacent target copy can sound prescriptive

Evidence: GLP-1 target copy says `A common starting point while appetite is
suppressed`; the onboarding page presents hard-coded fallback values such as
100 g and 70 g. Settings includes the disclaimer, but the onboarding target
page does not.

Impact: GLP-1 and bariatric users may read the app as assigning a clinical
target, even though the source comments and some prose defer to the user or
clinic.

Requested remediation: make the user/clinician-provided number the primary
instruction, make any fallback an optional neutral starting point, and place the
non-diagnostic disclaimer beside the suggestion on onboarding.

### F-013, P2, body-weight suggestion permission path is incomplete

Evidence: `HealthKitService` defines `requestBodyMassAuthorization`, while
onboarding calls `fetchBodyMassKilograms` without calling that authorization
method. The Info.plist promises body weight is read if the user asks for a
suggestion.

Impact: fresh users with a body weight in Health may not receive the intended
weight-based suggestion and get a hard-coded fallback instead. The user has no
way to understand why the suggestion did not use their weight.

Requested remediation: either request body-mass read access with explicit
consent and a clear explanation, or remove the implicit promise and present the
fallback as the normal behavior.

### F-014, P2, Sources wording overstates what the query proves

Evidence: Sources labels rows `Writing protein today`, but rows are built from
samples in the day window and can be stale. The freshness value helps, but the
headline still describes current activity.

Impact: users may think an app is actively writing now when it only wrote hours
ago, or may misdiagnose a delayed source as current.

Requested remediation: use wording such as `Contributing sources today` and let
the timestamp communicate recency. Reserve “writing now” for an observer-backed
state if one exists.

### F-015, P2, paywall lifetime and legal text need stronger scanability

Evidence: the lifetime card showed only `$29.99` until selected. The one-time
language appeared in the selected disclosure. Legal text and footer links were
small in the full paywall and offer sheets.

Impact: the user can miss the lifetime purchase type or struggle to read the
subscription terms before committing.

Requested remediation: put `One-time` or `Lifetime` on the card itself and
increase the minimum legal text size/contrast while retaining the required
disclosure.

### F-016, P2, manual review prompt makes a false target-hit claim

Evidence: Settings can present the enjoyment step without passive eligibility.
The step says `You have hit your protein target a few days running`. The audit
simulator did not have that history when the manual prompt was opened.

Impact: a user can see a personalized assertion that is not true, reducing trust
in the review request and the data model.

Requested remediation: use neutral copy for the manual Settings route, or make
the route follow the same eligibility check as the passive prompt.

### F-017, P1, feedback can close without delivery confirmation

Evidence: after entering feedback and tapping Send feedback on the headless
simulator, no Mail composer appeared and the sheet returned to Settings. The
code calls `UIApplication.shared.open(url)` and finishes without checking the
completion result.

Impact: a user without a configured Mail client can believe feedback was sent
when it was not, and the typed text is no longer visible.

Requested remediation: check whether the mail URL opened, keep the sheet open or
show an actionable fallback when it did not, and never mark feedback submitted
until the handoff succeeds.

### F-018, P1, feedback editor and locked switches have blank accessibility labels

Evidence: runtime snapshots exposed the feedback editor as `text-field` with an
empty label. The reminder/local override switch entries also appeared as blank
switches, and stale duplicated switches were actionable from inactive tabs.

Impact: VoiceOver users cannot identify the editor or locked feature, and
assistive automation can activate the wrong control.

Requested remediation: label the editor from its prompt, label every switch with
feature and state, make locked feature rows buttons when they are not real
switches, and resolve the inactive-tab issue in F-003 first.

### F-019, P2, one-tap logging has no post-window correction path

Evidence: Undo is available for eight seconds and then disappears by design.
There is no edit or delete control in Today or History.

Impact: a user who notices a wrong amount after the short window cannot correct
their total in the product. The HealthKit sample may remain available to other
apps even when the user knows it is wrong.

Requested remediation: decide whether the eight-second model is a deliberate
product constraint. If so, make it explicit in onboarding or provide a later
history correction path. Do not let a future fix accidentally create a second
source of truth.

### F-020, P1, circular widgets and complications show zero over target

Evidence: `ProteinWidget.swift` accessory circular uses `entry.remaining` as the
current value label. `WatchComplication.swift` accessory circular and corner
families do the same. `remaining` is clamped to zero when total exceeds target,
while `remainingHeadline` and `compactRemaining` correctly expose overage in
other families.

Impact: a user looking at a circular widget or circular/corner complication can
see zero instead of `25 g over`, exactly when the status differs from a normal
zero-left state.

Requested remediation: use the same overage-aware formatter in every family and
add snapshot coverage for under, exact, and over-target values.

### F-021, P2, body and legal copy is dense at small surfaces

Evidence: trial sheet disclosures, paywall legal footer, Settings Health footer,
and review footers were small and low contrast in screenshots. The long Health
paragraph is especially dense.

Impact: required terms and important recovery instructions are technically
present but practically easy to skip.

Requested remediation: shorten copy before reducing type, raise contrast for
secondary text, and test at Dynamic Type large and accessibility sizes.

### F-022, P3, review copy repeats the product name awkwardly

Evidence: the review pitch says `helps more people find a protein tracker that
is only a protein tracker`.

Impact: the line breaks the otherwise direct voice and sounds like marketing
copy written for the product rather than a person.

Requested remediation: use a shorter, natural sentence that explains the
single-purpose benefit once.

### F-023, P2, purchase and entitlement propagation remain unverified

Evidence: the simulator paywall loaded local fixture products, but
`StoreService.purchase` returns nil when RevenueCat is not configured on a
simulator. The release guide states that no real purchase has yet been made.

Impact: product loading is proven, but the most important conversion state is
not. The phone, widget, watch, restore path, trial eligibility, cancellation,
and lifetime entitlement are still release risks.

Requested remediation: perform sandbox/TestFlight purchases for monthly, yearly,
and lifetime, restore on a second device, confirm the entitlement mirror, and
verify the free watch/complication behavior before and after entitlement changes.

### F-024, P1, external HealthKit import remains an unverified product promise

Evidence: the app is built around readable `dietaryProtein` samples and the
Sources screen is populated from them, but no real device test with an external
food logger was available in this audit.

Impact: if common food loggers do not write readable dietary protein samples,
the main import and source-control promise degrades to an empty screen.

Requested remediation: run a real-device matrix with at least one writer per
candidate app, check source names, write timing, deletion behavior, stale rows,
and duplicate meals. Update product copy before submission if the import claim
does not hold.

## Re-test matrix for the fixing agent

After fixes, rerun each item rather than relying only on unit tests:

1. Fresh install, allow HealthKit, complete free onboarding, and verify the
   first Today read state.
2. Fresh install, deny all HealthKit categories, complete onboarding, confirm
   honest read/write statuses, Today recovery card, Settings recovery, and
   Sources recovery.
3. Deny writes only, log several local entries, undo one, close/reopen, check
   Today, Sources, History, widget cache, and migration after permission is
   granted.
4. Add external samples from two sources, toggle one off, reload, relaunch, and
   verify totals and duplicate warning.
5. Exercise under-target, exact-target, and over-target states on phone, iOS
   widget families, watch app, and every watch complication family.
6. Test the last visible History row and final Settings section at the bottom of
   scroll, including large text.
7. Walk VoiceOver through every tab with no invisible controls, then through
   onboarding slider, Settings slider, reminder, source toggle, gram picker,
   review form, paywall, and restore.
8. Enable reminders with zero grams, partial grams, and a completed target. Deny
   notification permission and revoke it later. Inspect pending request body and
   UI state.
9. Test the onboarding trial page at narrow phone width, large text, used-trial
   copy, product-loading failure, and long localized price.
10. Sandbox-purchase monthly, yearly, and lifetime. Cancel, restore, reinstall,
    and confirm the entitlement mirror on phone, widget, watch app, and
    complication.
11. Upgrade from the prior build to exercise What's New, then test a fresh
    install to ensure the announcement does not appear before onboarding.
12. Use a real phone and external food logger to validate `dietaryProtein` read,
    source grouping, timestamps, duplicate behavior, and background refresh.

## Second-pass re-analysis

The audit was reread after the initial screen walkthrough and checked against
the source routes, the product guide, the WidgetKit targets, and the observed
denied-permission state. The second pass added or confirmed the following items
that are easy to miss in a happy-path review:

- Local fallback entries are included in the cache and History but omitted from
  Today source rows and Sources empty state. This is a cross-surface data
  contradiction, not just a copy issue.
- `isAuthorized` means that the HealthKit request sheet was answered, while the
  Settings UI presents it as verified read connectivity. The denied path was
  repeated with a fresh install to confirm the mismatch.
- The root accessibility issue is broader than a missing label. The inactive
  tabs remain actionable, and stale references were observed activating the
  wrong Settings switch and a purchase sheet.
- The reminder path was checked in source after the runtime switch could not be
  reliably targeted. The hard-coded zero total and ignored authorization result
  are concrete logic issues even without waiting for a notification to fire.
- Widget and complication formatter use were checked family by family. The
  over-target defect is limited to circular and corner families, while other
  families already use overage-aware helpers.
- Watch runtime verification is not claimed. The generic watch target build
  succeeded, but the checked-out watchOS 26.2 destination was rejected by both
  Xcode and `simctl`. This remains a required follow-up rather than an inferred
  product failure.
- No app source or project file was changed. The only intended artifact from
  this task is this audit document.

## Remediation log (2026-08-06, build 6)

Every finding below was re-checked against the source before acting. Four were
not reproduced in code and are recorded as such rather than "fixed".

Fixed:

- **F-001 / F-008** `HealthReadState` replaces the `isAuthorized` claim.
  Settings reports evidence (`Receiving data` / `No data yet` / `Not set up`)
  and never green without a sample having actually arrived; the state is backed
  by `hasEverReadSamples`, persisted in the App Group and set only from the
  HealthKit fetch. Today and Sources both show a recovery card whenever nothing
  has ever been read, branching between "Connect" and "Open Apple Health".
  Health footer copy is now per-state instead of one paragraph.
- **F-002** Local-only entries are converted to `ProteinSample`s marked
  `isLocalOnly` and merged into `todaySamples`, so one sum over one list feeds
  the total, the Today source card, and the Sources screen. `ProteinSourceStatus
  .localOnlyGrams` drives a row note naming the grams still waiting for Health.
  Today and the watch stopped adding local grams a second time (that path would
  have double-counted once the merge landed).
- **F-004 / F-018** Accessibility names/values on both target sliders, the
  preset steppers (with the duplicate visible amount hidden), the source
  toggles, the locked Protein+ switches, and the feedback editor.
- **F-006** The reminder now schedules from the reconciled total, reschedules on
  every reconcile and when the hour picker moves, and hitting the target skips
  one occurrence instead of deleting the request. `reminderEnabled` is persisted
  only after `UNUserNotificationCenter` reports authorization, with a
  `Notifications are off` row routing to iOS Settings.
- **F-010** The all-zero day list is hidden; the chart card is the single empty
  statement.
- **F-012** The non-diagnostic disclaimer now sits beside the suggested number
  on the onboarding target page, not only in Settings.
- **F-013** A "Suggest from my body weight" button on the target page requests
  body-mass read access, which is the consent the Info.plist describes. Without
  it the fetch was unauthorized and every user silently got the fallback.
- **F-014** Sources header is `Counting today`.
- **F-015** The lifetime card carries `One-time purchase` before selection.
- **F-016** The Settings route passes `earnedByTargetHits: false` and uses copy
  that claims no streak.
- **F-017** `open(_:options:completionHandler:)` gates the outcome; a failed
  handoff keeps the sheet and the typed text, shows the address, and does not
  mark feedback submitted.
- **F-020** `ProteinFormat.gaugeValue` / `gaugeGrams` make the iOS circular
  widget and the watch circular and corner families overage-aware, with unit
  tests for under, exact, and over target.
- **F-022** Review pitch line rewritten.
- **F-005** The onboarding billed amount sits in its own surface. Note the
  reported collision was not reproducible in the layout: `BilledAmountBlock` is
  a full-width centred row 18 pt below the selling points, so it cannot overlap
  them. The isolation is a readability improvement, not a bug fix.

Not reproduced in code, no change made:

- **F-003** Inactive tabs are already `accessibilityHidden` at both the
  `NavigationStack` and its hosted content, plus `allowsHitTesting(false)` and
  `opacity(0)`. A snapshot tool that ignores those attributes will still list
  the elements; VoiceOver and touch will not reach them.
- **F-009** Each tab reserves 92 pt via `safeAreaInset(edge: .bottom)` against a
  capsule whose top edge sits 68 pt off the screen bottom, so end-of-scroll
  content clears it by 24 pt. The capsule does float over content mid-scroll,
  which is the intended behaviour of a floating bar. Worth one runtime check at
  the largest text size before submission.
- **F-011, F-019, F-021** Product decisions or subjective polish, left alone.
- **F-007** Choosing between `Protein` (home screen, Health sheet) and `Protein
  Tracker` (metadata, in-app) is an ASO call, not a defect fix. Left for Jack.
- **F-023, F-024** Device-only verification, already tracked in the project
  guide.

Tests: 55 passing (was 49). All four targets build.

## Final audit disposition

The app has a strong product spine and a mostly coherent visual system. Fix the
HealthKit permission truthfulness, local fallback provenance, accessibility tree,
reminder math, over-target widgets/complications, and onboarding price layout
before treating the build as release-ready. Complete the real-device purchase,
external HealthKit import, and compatible watch runtime passes before submission.
