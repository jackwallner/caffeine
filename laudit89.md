# Protein Tracker end-to-end user audit

Audit date: 2026-08-09

Build reviewed: 1.0.0 (8)

Commit reviewed: 4f269c9

Scope: end-to-end user experience, bugs, confusing states, personas, accessibility, HealthKit, Apple Watch, widgets, freemium boundaries, purchase surfaces, privacy expectations, and recovery paths. This is an audit only. No application code was changed.

## Executive verdict

The product has a strong and unusually clear spine: one target, one total, and a useful answer on the wrist. The current build is materially better than the older audit state. HealthKit denial is now described more honestly, local phone entries are visible in Sources, empty History no longer renders a misleading list of zero rows, over-target values are handled in the main app and widget code, the onboarding price block is isolated, medical-adjacent target copy is cautious, and feedback has a no-Mail fallback.

There are no confirmed crashes or P0 data-loss failures in the exercised flows. The most important current risks are:

1. The tab architecture still produces an accessibility tree that does not match the visible screen. Hidden Settings controls leak into other tabs, while the visible Settings form can be absent from the initial accessibility tree. This is a release blocker for VoiceOver and assistive interaction.
2. Source exclusions are not mirrored to the Watch. A user can turn off an external source on the iPhone and still see that source counted on the Watch.
3. The Watch write-denied fallback is device-local, is not carried to the iPhone, and is not retried by the Watch app after authorization changes. This directly threatens the wrist-first promise for users who deny HealthKit write access.
4. External HealthKit import and real purchases remain unverified on physical devices. They are product submission blockers even though they are not confirmed defects in the simulator.
5. Settings has no precise numeric target entry after onboarding. Users with an exact target, including GLP-1 and post-bariatric users, must drag a 1 gram slider.
6. The fixed bottom tab capsule visibly covers lower History and Settings content.

Severity:

- P0: data loss, security issue, crash, or unusable primary flow.
- P1: release-blocking correctness, trust, accessibility, or monetization issue.
- P2: meaningful usability, recovery, layout, or edge-state issue.
- P3: polish, copy, or low-risk improvement.

Confidence:

- Confirmed: observed in the running app or directly demonstrated by source and runtime behavior.
- Source-based: deterministic from the current implementation but needs a device or multi-source pass for the final reproduction.
- Verification gap: the product promise cannot be signed off until the listed real-device test is run.

## Audit method

### Runtime surfaces exercised

- Fresh iPhone onboarding from welcome through reason selection, target entry, trial offer, and free exit.
- Strength, GLP-1, bariatric, and general-persona copy by runtime and source review.
- HealthKit authorization sheet, including the current read/write explanation and write-denied behavior.
- Free Today with no data, locked quick-add controls, the personalized Protein+ offer, and Apple Health recovery.
- Protein+ Today with local fallback entries, over-target totals, Sources, History, Settings, feedback, and the full paywall.
- iPhone target and reason controls, quick-add settings, reminder settings, appearance, legal/support rows, and the persistent tab bar.
- Apple Watch installation, entitlement propagation, wrist logging, custom amount picker, edit entry point, and the compact layout.
- Widget and complication implementation, including over-target formatting and live target reads.
- Accessibility tree snapshots while Today, History, Settings, Sources, paywall, and feedback were active.
- Current source review against the previous audit in audit86.md, with old findings marked fixed where verified.

### Devices and builds

- iPhone 17 Pro, iOS 26.5, shared headless simulator group 7, UDID 978FE567-2056-428F-965D-D9F6A90F04B6.
- Paired Apple Watch Series 11 46 mm, watchOS 26.5, shared headless simulator group 7/8, UDID BCDBFB27-A122-4644-9878-D8451BA793F6.
- Protein iPhone target built and launched successfully.
- ProteinWatch target built, installed, and launched successfully.
- 57 unit tests passed, 0 failed, 0 skipped.

### Deliberate limitations

- No physical iPhone or Apple Watch was used.
- No real purchase was made through App Store sandbox or TestFlight.
- No external food logger was installed and verified as a dietaryProtein writer.
- Widgets and complications were source-reviewed and built, but not placed on a real Home Screen or watch face.
- The tested Watch runtime was 46 mm, not 41 mm.
- Dynamic Type extremes, actual VoiceOver focus navigation, Reduce Motion, right-to-left text, and localization were not exhaustively rendered.
- Simulator purchase behavior is intentionally disabled, so a successful local paywall render is not evidence of a successful transaction.

## Persona matrix

| Persona | Main journey | Result | Main risk |
| --- | --- | --- | --- |
| Privacy-conscious new user | Welcome, HealthKit decision, free setup | The product promise is clear and the system explanation is good | “Stays on your device” is broader than the actual Apple Health and purchase-service data flow |
| Lifter | Strength reason, suggested target, phone logging, Watch | Fast and focused; over-target state is readable | Exact target editing later requires dragging |
| GLP-1 user | Manual target, free setup, optional upgrade | Current copy tells the user to enter the target already used or given | No Back path if the user chooses the wrong reason; exact target editing after setup is slow |
| Post-bariatric user | Clinic target, HealthKit, history | The current onboarding instruction defers to the clinic target | The user must finish onboarding before correcting a wrong persona selection |
| General health user | General reason and target | Calm, non-judgmental flow | “Sensible starting point” still sounds like an app recommendation |
| Free Apple Health reader | Existing food logger data, source controls, widget, history | Read-only value proposition is present | Real-world dietaryProtein import is not verified |
| User who denies read access | Deny HealthKit, finish setup, recover later | Current screen says no data rather than connected | The recovery state relies on Apple Health settings and historical evidence limits |
| User who denies write access | Log from iPhone, use local fallback | Phone total, banner, Sources row, and History are coherent | Watch fallback can diverge and never migrate automatically |
| Protein+ phone logger | Presets, Other amount, undo, correction list | Fast logging and later correction list work | Rapid taps and failed undo outcomes are not serialized or surfaced |
| Watch-first Protein+ user | Phone unlock, Watch settings sync, wrist log | Entitlement and target sync worked in the tested pair | Source exclusions and local fallback are not synchronized |
| Multi-source logger | Sources, duplicate warning, exclusion | Source provenance and exclusion model are understandable | An exclusion disappears from the UI when that source has no sample today |
| User over target | Continue logging past the target | Phone and current widget/complication format helpers say grams over | The ring uses a second green arc that may need explanation |
| Accessibility user | VoiceOver, large text, motor adjustment | Several important controls now have labels | Hidden tabs and duplicate unlabeled controls make navigation unreliable |
| Older or low-vision user | Settings, paywall, legal, support | Large primary numbers and buttons are good | Small disclosure text, dense Health copy, and the bottom overlay reduce scanability |
| User with no Mail app | Feedback form, send | Current fallback keeps the text and gives a copyable address | App Store review handoff still does not verify that the store opened |
| Returning subscriber | Expiry, restore, Watch entitlement | Restore and entitlement mirroring are present in source | Pending purchase and entitlement downgrade states need a device pass |

## Findings

### LA-001, P1, Confirmed: inactive tabs leak into accessibility and the active Settings form can disappear

Affected personas: VoiceOver users, switch-control users, users relying on assistive automation, and anyone navigating a dense screen by semantic controls.

Observed behavior:

- MainTabView keeps Today, History, and Settings NavigationStacks alive in one ZStack.
- While Settings was visibly on screen, an initial and repeated runtime accessibility snapshot exposed only the three tab buttons, not the visible Apple Health, target, or quick-add controls.
- After scrolling, the snapshot exposed the visible Settings controls plus duplicate switch targets with blank labels.
- While another tab was active in the earlier pass, Settings controls such as Theme, Restore Purchases, Rate, Send feedback, Privacy, and Terms appeared in the accessibility tree even though they were not visible.
- The source attempts to hide inactive stacks with opacity, hit testing, accessibilityHidden, and an inner accessibilityHidden modifier, but the runtime tree still did not match the visible screen.

Impact:

VoiceOver focus can move through controls that are not visible. A user can hear a Settings switch while reading History, or reach the tab bar without ever finding the visible Settings form. Assistive automation can also act on stale controls from the wrong tab. This is the most important current accessibility defect.

Reproduction:

1. Launch a completed setup.
2. Select Settings and inspect the accessibility tree before scrolling.
3. Scroll Settings and inspect again.
4. Select History and inspect the tree for Settings controls.

Evidence in code: Protein/App.swift, MainTabView and tabContent around lines 112 to 225, plus tabVisibility around lines 245 to 251.

Follow-up required: validate with actual VoiceOver focus movement on a physical device after changing the tab mounting or visibility model. A clean snapshot for each tab is required, including while a sheet is open.

### LA-002, P1, Source-based: iPhone source exclusions are not sent to the Watch

Affected personas: multi-source users, users with duplicated food logging, and anyone who trusts the Watch number during the day.

Observed implementation:

- GoalSettings persists excludedSourceBundleIDs on the iPhone.
- The WatchSettingsPayload only contains targetGrams, quickAddPresets, isPro, and hasCompletedSetup.
- WatchConnectivity therefore mirrors the target, presets, entitlement, and setup state, but not source exclusions.
- The Watch computes its own total with its local sourceSelection, which defaults to no exclusions unless that state arrives by another route.

Impact:

A user can discover that MyFitnessPal and another logger are both contributing, turn one off on the iPhone, and see the corrected iPhone total. The Watch can continue counting the excluded app and show a higher grams-left or overage result. This breaks the single-source-of-truth experience exactly where the app promises a wrist number.

Reproduction needed:

1. Use a device pair with at least one external dietaryProtein source.
2. Exclude that source in iPhone Sources.
3. Keep the Watch app open or relaunch it.
4. Compare the iPhone and Watch totals.

Evidence in code: Shared/Services/GoalSettings.swift lines 62 to 69 and 136 to 139, and Shared/Services/WatchSyncService.swift lines 12 to 54.

### LA-003, P1, Confirmed on simulator and source: Watch write-denied entries diverge and never retry

Affected personas: Watch-first Protein+ users who deny or have not yet granted HealthKit write access.

Observed behavior:

- The iPhone was run with HealthKit writes denied and logged local-only entries. Its Today total reached 240 g and showed the local fallback banner.
- The Watch was then run with the same paired setup and logged 40 g locally. The Watch showed 40 g, while the iPhone remained at 240 g. The Watch entry did not appear in the phone total.
- The architecture intentionally does not use a WatchConnectivity entry queue.
- The iPhone app calls retryPendingLocalEntries when entering the foreground and from relevant Apple Health paths.
- The Watch app calls refreshCache on launch and background refresh, but does not call retryPendingLocalEntries.

Impact:

The Watch can show a number that is not on the phone, and a local Watch entry can remain local even after the user later grants write access. The user has no clear way to know which device has the authoritative local fallback. The current Watch locked or fallback experience also has no banner equivalent to the iPhone’s Saved on this device only notice.

This is not just a synchronization delay. It is a permanently different data path for the exact HealthKit denial state the product deliberately supports.

Evidence in code: ProteinWatch/App.swift lines 23 to 29 and 32 to 39, Shared/Services/ProteinLogService.swift lines 116 to 141, and Shared/Services/WatchSyncService.swift lines 46 to 55.

Required device acceptance cases:

- Deny write access on the Watch, log, then open the iPhone.
- Grant write access later and relaunch the Watch.
- Log while the iPhone is asleep or unavailable.
- Reconnect the pair and confirm total, Sources, History, widget, and complication agree.

### LA-004, P1, Verification gap: external dietaryProtein import is not signed off

Affected personas: free users whose primary value is importing existing food logs, source-control users, and App Store reviewers following the import promise.

The app depends on other food loggers writing readable HealthKit dietaryProtein samples. The source query, source grouping, timestamp display, and exclusion rules are coherent, and the simulator fixture rendered a MyFitnessPal source. That is not evidence that a real MyFitnessPal, MacroFactor, Cronometer, or other candidate app writes the type in a way this app can read.

Impact:

If the common writers do not expose usable dietaryProtein samples, a new user can grant access and still see an empty Today or Sources screen. The product then feels broken even though the app’s own code is behaving as designed.

Required physical-device matrix:

- Install at least one likely external writer per target audience.
- Log a meal in each writer.
- Confirm the sample appears under the expected source name and time.
- Confirm delays, edits, deletions, multiple meals, and source exclusion.
- Confirm the app’s own entry is not double-counted after an external app imports it.

This remains an open product risk from the project guide, not a confirmed simulator defect.

### LA-005, P1, Source-based and verification gap: pending purchases have no user-facing state, and real purchases remain unverified

Affected personas: trial users, users with Ask to Buy or delayed billing, users restoring on a second device, and users upgrading from the Watch.

Observed implementation:

- RevenueCat purchase states include purchased, cancelled, and pending.
- PlusGate treats pending the same as purchased for presentation and dismisses the offer sheet.
- Onboarding starts the yearly purchase and ignores the returned purchase state, relying only on a later isPro change.
- The simulator purchase path intentionally returns no state because RevenueCat is not configured.
- The paywall and offer surfaces were visually exercised with local StoreKit fixture products, not a transaction.

Impact:

When a purchase is pending, the user can be returned to the free app with no clear explanation and no visible “purchase pending” or “we will unlock when Apple confirms” state. The user may retry, restore repeatedly, or assume the purchase failed. A real device pass is also needed to confirm trial eligibility, cancellation, restore, entitlement cache, Watch propagation, widget behavior, and lifetime access.

Required physical-device acceptance:

- Buy monthly, yearly, and lifetime in sandbox/TestFlight.
- Test eligible and ineligible trial accounts.
- Cancel the Apple confirmation sheet.
- Exercise a pending purchase.
- Restore on a second phone.
- Confirm entitlement reaches the iPhone, Watch, widget, and complication.
- Confirm expiry or revocation returns the correct free features.

### LA-006, P2, Source-based: historical HealthKit evidence can look like current read access after revocation

Affected personas: privacy-conscious users who change Health permissions, users whose food logger stops writing, and users troubleshooting a stale total.

The current fresh-denial state is much better than the previous build. It shows Not set up or No data yet rather than claiming Connected. However, HealthKitService persists hasEverReadSamples forever once any sample has been read. The Settings chip then says Data received whenever isAuthorized is true and historical evidence exists.

If the user later revokes read access, or if HealthKit returns no samples after a previously successful day, the app can still show Data received even though there is no current evidence. Today can lose the prominent connection recovery card because the state remains receiving.

Apple does not expose the read authorization answer, so this is a product-language limitation rather than a simple permission check. The UI should distinguish “data received previously” from “data received in this read,” and a physical-device permission-revocation pass is required to confirm the exact system behavior.

Evidence in code: Shared/Services/HealthKitService.swift lines 21 to 29, 54 to 63, 68 to 79, and 349 to 359.

### LA-007, P2, Confirmed: Settings has no precise numeric target entry

Affected personas: GLP-1 users, post-bariatric users with a clinic value, lifters with a calculated value, and users with motor or precision limitations.

Onboarding allows text entry for a manual target. After setup, Settings shows the current number and a 1 gram slider from 20 to 400, but no text field or direct numeric editor.

Impact:

A user who needs 73 g, 117 g, or another exact clinician-provided value must drag through many slider positions. The visible number looks like a value that could be edited directly, but tapping it does not offer a numeric field. This is especially awkward for the medical-adjacent personas the app explicitly supports.

Evidence in code: OnboardingView.swift uses a TextField around lines 277 to 288, while SettingsView.swift uses only a Slider around lines 143 to 168. The behavior was visible on the running Settings screen.

### LA-008, P2, Source-based: changing the target does not immediately refresh history or the reminder

Affected personas: returning users who adjust a target, users with an evening reminder, and users who compare phone, History, widget, and Watch numbers after a change.

GoalSettings saves and pushes targetGrams to the Watch, so the Today hero and Watch target update. The current day cache and History target snapshot are written by HealthKitService.refreshCache. Settings does not trigger a refresh when targetGrams changes, and History reloads only when the Pro window changes.

Likely user-visible results:

- The Today hero shows the new target immediately.
- The current History row or target line can continue showing the old target until another refresh or navigation lifecycle reload.
- An enabled reminder can retain an old notification body and old met-target decision until the next reconciliation.

This is a consistency problem rather than a total arithmetic problem. It is important because the product promises an exact reminder amount and a shared target across surfaces.

Evidence in code: GoalSettings.swift lines 40 to 51, SettingsView.swift lines 143 to 168 and 298 to 311, and HealthKitService.swift lines 349 to 382.

### LA-009, P2, Confirmed: floating tab capsule occludes scroll content

Affected personas: History users, Settings users, older users, and users with larger text.

The fixed capsule at the bottom of MainTabView visibly overlays the lower History list. In the 30-day runtime pass, the bottom visible History row was partly behind the Today, History, Settings capsule. The Settings pass also showed the capsule across lower content while scrolling through support and About.

Impact:

The user can infer that content continues, but cannot read or confidently interact with the row underneath. This is most noticeable on the long History list and at the end of Settings, where the user expects the last section to be fully visible.

Evidence in code: MainTabView ignores the bottom safe area and adds a fixed tab capsule in Protein/App.swift lines 112 to 129. The tab stack reserves 92 points, but the individual scroll views use only 24 points of bottom padding. The occlusion was visible on the 368 by 800 iPhone viewport.

### LA-010, P1 accessibility and P2 interaction: locked reminder controls are real switches with duplicate blank switch entries

Affected personas: VoiceOver users, users with cognitive or motor impairments, and free users trying to understand what Protein+ includes.

The free Settings screen presents the evening reminder as a Toggle with a lock icon. Tapping the switch opens the Protein+ offer rather than changing a setting. That is understandable visually, but semantically it is not a switch the user can turn on.

In the runtime accessibility tree, the visible labeled reminder switch was accompanied by another blank switch entry. Local Pro override showed the same pattern in the DEBUG audit build. The source explicitly adds an accessibility label and hint to proToggle, but hidden duplicate controls from the tab stack still surfaced.

Impact:

VoiceOver users can encounter a blank switch and cannot tell whether it is the reminder or another control. A free user can also interpret the locked switch as a broken setting because the switch briefly behaves like a setting before presenting an offer.

Evidence in code: SettingsView.swift lines 333 to 374 and the tab architecture in Protein/App.swift. Runtime Settings snapshots showed labeled and blank switch targets at the same time.

### LA-011, P2, Confirmed: onboarding has no Back control or progress signal

Affected personas: new users, GLP-1 and post-bariatric users selecting a sensitive persona, users who change their mind about the target, and users who need to understand how much setup remains.

The onboarding steps are welcome, reason, target, and trial. Continue moves forward, but there is no Back control and no progress indicator. The reason can be changed later in Settings, but only after the user finishes the rest of onboarding and reaches the main app.

Impact:

A user who chooses the wrong reason on the target screen cannot return to the reason screen. A user who wants to review or change a target before seeing the trial page has to finish setup, exit to the app, and find Settings. The absence of progress also makes the final trial offer feel less predictable.

There is a second, smaller issue on the welcome transition: the HealthKit request runs in a Task while the UI immediately moves to the reason page. The system sheet normally blocks interaction, but there is no in-app pending indicator if authorization takes time.

Evidence in code: OnboardingView.swift lines 12 to 17 and 472 to 497.

### LA-012, P2, Source-based: remembered source exclusions disappear when the source has no sample today

Affected personas: multi-source users, users diagnosing duplicate entries, and users who change food logging apps.

Excluded source bundle IDs persist in GoalSettings, but SourcesView only renders sources that have samples in the current day. If a user excludes an app today and that app writes nothing tomorrow, the app is no longer listed and there is no visible remembered-exclusion list from which to turn it back on.

Impact:

The user can make a persistent choice and then lose the UI control needed to reverse it. They may believe the exclusion was forgotten or may have to wait for the source to write again before recovering the setting.

Evidence in code: SourcesView.swift builds rows from health.todaySamples, while GoalSettings persists excludedSourceBundleIDs independently.

### LA-013, P2, Confirmed layout and source risk: Watch recovery and accessibility are thinner than iPhone recovery

Affected personas: Watch-first users, users who deny HealthKit on the Watch, VoiceOver Watch users, and users on the smallest supported Watch.

The tested 46 mm Watch layout was compact and readable. It showed a useful free lock notice, three large presets, Other, and Edit after the entitlement arrived. The custom Watch picker showed a Digital Crown value and Add button.

Remaining issues:

- WatchGramPicker has no explicit accessibility label or hint for the selected grams or the Digital Crown adjustment. The visible 25 g value is not enough to guarantee a good VoiceOver experience.
- The Watch has no visible Apple Health recovery action comparable to the iPhone’s Open Apple Health path.
- The free lock notice tells the user to open Protein Tracker on the iPhone, but it is informational rather than an actionable route.
- The requested 41 mm above-the-fold layout was not runtime-tested. The source is designed for it, but the tested 46 mm result cannot prove the 41 mm result.

Evidence in code: ProteinWatch/Views/WatchTodayView.swift lines 45 to 84 and 270 to 295.

### LA-014, P2, Source-based: iPhone correction UI can present Watch entries as deletable app entries

Affected personas: users who log on both phone and Watch, and users trying to correct an imported or paired-device entry.

The iPhone Review today’s entries sheet filters all entries marked as ours, including entries saved by the Watch. Every row presents a trash button. If the iPhone cannot delete a Watch-created HealthKit sample, the user only learns that after tapping the button and seeing an alert that tells them to remove it in Apple Health.

Impact:

The initial affordance says the app can correct the entry, but the result can be a failure with a separate Apple Health instruction. The row does not identify whether it came from iPhone or Watch before the user attempts deletion.

Evidence in code: TodayView.swift OwnEntryReviewSheet, especially the row and failure alert near the end of the file. A paired-device HealthKit write/delete pass is still required to confirm which samples iOS allows the phone bundle to delete.

### LA-015, P2, Source-based: undo failures are silent and rapid logs can race

Affected personas: fast one-tap loggers, Watch users, and anyone who double-taps after a missed touch.

Each preset tap starts a separate Task. ProteinLogService stores only one session-scoped lastEntry. If several taps complete out of order, the single Undo action can refer to a different completed entry than the user believes was the last tap.

The Today and Watch undo handlers also ignore the Bool result from undoLast and always hide the Undo affordance. If the HealthKit object cannot be found, deletion fails, or a SwiftData save fails, the user sees the confirmation row disappear even though the total may remain unchanged.

The eight-second window made a perfect automated timing reproduction difficult, but the behavior is deterministic from the current source.

Evidence in code: TodayView.swift lines 225 to 237 and 390 to 418, ProteinWatch/Views/WatchTodayView.swift lines 168 to 181 and 199 to 211, and ProteinLogService.swift lines 60 to 82.

Additional migration edge case: if a local entry is migrated into HealthKit while lastEntry still points at the local ID, undo can delete the local row while leaving the newly created HealthKit sample in place. This needs a device or controlled authorization-transition test.

### LA-016, P2, Source-based: entitlement downgrade does not cancel an existing reminder

Affected personas: subscribers whose entitlement expires or is revoked, and users who use restore or account changes across devices.

When the user turns off the reminder, Settings explicitly calls cancelReminder. When the entitlement changes from Pro to free, StoreService updates the cache and Watch state, but no corresponding notification cancellation is performed. HealthKitService only reschedules while the entitlement is still Pro.

Impact:

A reminder request created while Pro can continue to fire after the user is no longer entitled to the reminder feature. The Settings UI will show the free locked state, but the operating system may still deliver the old notification.

This is an edge state that needs a real entitlement-expiry or controlled local-override test. It is a product-boundary bug if confirmed.

### LA-017, P2, Trust and privacy copy: “never leaves your devices” is broader than the actual data model

Affected personas: privacy-conscious users, HealthKit users, and subscribers deciding whether to connect Apple Health or purchase.

Onboarding says “Your data never leaves your devices” and the trust line says “Stays on your device. No account.” The app does not appear to send health samples to its own server, which is the useful promise. However:

- HealthKit is intentionally used to share entries across paired Apple devices and with other HealthKit apps.
- Production RevenueCat necessarily receives purchase and entitlement information.
- Paywall impression and purchase service calls leave the device.
- Feedback intentionally opens a mail draft when the user chooses to send it.

Impact:

A literal reader can interpret the copy as “no information leaves this device,” which conflicts with HealthKit synchronization, purchase-service traffic, and the explicit feedback handoff. The health-data claim should be narrower than the all-data claim.

This is primarily a trust and policy-copy review item, not a confirmed health-data transmission defect.

### LA-018, P2, Legal and disclosure text is present but hard to scan on compact surfaces

Affected personas: low-vision users, older users, users on smaller phones, and users making a paid decision under time pressure.

The full paywall, trial offer sheet, onboarding trial page, and Settings Health footer all contain the required information. On the 368 by 800 viewport, the paywall and offer legal text was small and low contrast relative to the primary CTA. The Health footer is useful but dense, combining permissions, data freshness, migration, and Apple Health navigation in one paragraph.

Impact:

The user can technically find terms and recovery instructions but is likely to skip or misunderstand them. Longer localized prices, larger text, and used-trial wording could push the fixed footer into a crowded state.

The current paywall did correctly show Lifetime as One-time purchase, and the onboarding price block no longer collided with the final selling point. Those older defects are fixed, but readability still needs a dynamic-type and localization pass.

### LA-019, P3, Over-target ring has a second visual arc without an explanation

Affected personas: users who exceed the target, low-vision users, and users who read the app as a one-number product.

The runtime phone over-target state correctly said 40 grams over and 200 / 160 g eaten today. The text is clear and the widget and complication format helpers now use overage-aware values.

The ring itself showed a full orange arc plus a green secondary arc. The green arc appears to represent the overage, but there is no legend or direct visual explanation. A user can read it as two goals or two progress measures.

This is not a correctness defect. It is a comprehension risk on a deliberately minimal interface. The text and accessibility label currently do most of the work.

### LA-020, P2, App Store review handoff does not verify that the store opened

Affected personas: users under restrictions, users without a functioning App Store link, and users who choose to support the app from the review funnel.

The feedback path now checks the mail handoff and keeps text visible when no Mail app exists. The review path is different: it calls UIApplication.open for the App Store review URL, marks the outcome, and dismisses without checking the completion result.

Impact:

If the App Store handoff fails, the user can be treated as having completed the review path and may not be prompted again, even though no review screen opened. This is lower priority than the feedback issue because App Store is normally present, but the two support flows should have the same handoff reliability standard.

## What worked and should not regress

These areas were exercised or checked against the older audit and are currently in a good state:

- The product value is obvious on the welcome screen: grams left, watch-first, no calorie or food-database sprawl.
- The current HealthKit system explanation names Protein Tracker and explains that declined writes remain on the device.
- Fresh no-data state now says Not set up, No data yet, or Nothing from Apple Health yet instead of claiming a denied read is connected.
- Phone local fallback is now coherent across the hero, fallback banner, Today source card, Sources sheet, correction list, and History.
- The Sources screen groups the app’s iPhone and Watch entries as one own source and identifies local-only grams as waiting for Apple Health.
- External source rows have timestamps, inclusion controls, and duplicate-risk messaging.
- Empty History no longer shows a chart message followed by a misleading list of seven explicit zero rows.
- The main phone hero correctly renders over-target copy.
- The current widget and complication source uses gaugeValue and overage-aware headline helpers. The older circular-zero defect was not present in the current source.
- The onboarding price is now isolated in its own billed-amount block. The runtime trial page did not reproduce the older price collision.
- The full paywall displayed Lifetime as One-time purchase, with clear Yearly and Monthly cadence labels.
- The paywall close button was exposed as Close in the runtime accessibility tree.
- The GLP-1 flow required a manually entered target and used the wording “already use or were given.” The bariatric flow defers to the clinic target. The target page includes a non-medical disclaimer.
- Manual review prompting now uses neutral copy rather than claiming a target streak.
- Feedback now labels the editor, preserves text, and shows a copyable fallback address when no Mail app is available.
- The Watch entitlement and target reached the paired Watch after launching the iPhone with Pro state. The 46 mm Watch screen remained compact and the preset layout was easy to read.
- The project builds both iPhone and Watch targets, and all 57 unit tests passed.

## Recommended release-gate order

1. Resolve the tab accessibility tree and re-run a real VoiceOver pass on every tab and sheet.
2. Define the cross-device source and fallback model. Test excluded sources, Watch write denial, later authorization, sleep, reconnect, History, widget, and complication.
3. Verify external dietaryProtein import on real devices before relying on the import promise in Store listing copy.
4. Complete a sandbox/TestFlight purchase matrix, including pending, cancellation, restore, trial eligibility, lifetime, expiry, and Watch entitlement propagation.
5. Add a precise Settings target editor or explicitly decide that dragging is the intended returning-user interaction.
6. Remove bottom-overlay occlusion at the end of every scroll, then test larger text and compact phones.
7. Test target changes and entitlement changes while a reminder is enabled.
8. Recheck 41 mm Watch, VoiceOver Watch picker behavior, and all widget/complication families on a real face.

