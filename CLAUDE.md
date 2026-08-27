# Global agent guidance

Canonical file. `~/AGENTS.md` and `~/.codex/AGENTS.md` are symlinks to it, so
Claude Code and Codex read exactly the same rules. Edit here; never replace a
symlink with a copy. Harness-specific tooling notes belong in the relevant
skill, not in a forked version of this file.

## Style

- Be direct and terse. No preamble, no trailing summaries, no emojis unless asked.
- Just do straightforward tasks, don't ask permission.
- Never use em dashes in prose. Use commas, parentheses, or separate sentences.

## Approach

- If a request has a load-bearing ambiguity, name it and ask one question before coding.
- Before non-trivial work, state the success criterion in one line. After, verify the result against it.

## Code

- Comfortable across the stack: Swift, Python, JS/TS, and shell.
- Prefer flat over nested. Keep functions short and focused.
- Group and sort imports: standard library, third-party, local.
- Use type hints in Python, TypeScript over plain JS when practical.

## Workflow

- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`.
- Always commit when the task is complete, and push when the repo has a remote.
- Commit only task-owned files and preserve unrelated working-tree changes.
- Run tests after changes if a test suite exists.
- Keep PRs focused, one concern per PR.
- Do not add Co-Authored-By lines to commits.

## iOS apps

- Load the `ios-dev` skill for build, release, pricing, or App Store work.
- Rerun `xcodegen generate` after adding or removing Swift files or editing `project.yml`.
- Use the shared headless simulator pool. Never open Simulator.app or build against a named destination.
- Never configure a production RevenueCat `appl_` key on a simulator run.
- Run `./scripts/testflight.sh` after every push that changes app code.
- Health and wellness apps must not claim to diagnose, treat, cure, or prevent a condition.
- Shared App Store Connect credentials live at `~/.baseball_credentials`.
- Fleet App Review phone: `4257533411`. Never put it in repository metadata.

## Subagent delegation

- Ask Jack which model to use before spawning a subagent.
- Spawn at most one subagent unless Jack explicitly approves more.
- A subagent must not spawn additional subagents.
- Use direct work when delegation is unnecessary.

## Browser use

- Use the existing Chrome profile through the Codex Chrome integration.
- Open a separate task window when practical.
- Do not launch an isolated Playwright browser unless Jack explicitly requests it.

--- project-doc ---

# Caffeine Tracker: Bedtime

Caffeine intake and bedtime forecasting. XcodeGen project and scheme:
`Caffeine`. Simulator lease owners: `caffeine` and `caffeine-watch`.

## Product

The app answers three separate questions:

1. How much caffeine did I consume today?
2. How much may remain in my system now and at bedtime?
3. What would another drink do before I log it?

The third question is the distinctive interaction. Every quick amount opens a
preview first. The user can change the dose and time, compare the current and
proposed bedtime estimates, see the dose-specific latest modeled time, and then
choose whether to log it.

Estimates use an exponential half-life model. They are not blood measurements,
medical advice, or safety cutoffs. The default half-life is 5 hours and the UI
also shows a 4 to 6 hour range.

## Stack and identifiers

- Swift 6, SwiftUI, SwiftData, HealthKit, WidgetKit, WatchConnectivity
- iOS 17+, watchOS 10+
- App: `com.jackwallner.caffeine`
- Widget: `com.jackwallner.caffeine.widget`
- Watch app: `com.jackwallner.caffeine.watch`
- Watch widget: `com.jackwallner.caffeine.watch.widget`
- Tests: `com.jackwallner.caffeine.tests`
- App Group: `group.com.jackwallner.caffeine`
- App Store Connect app: `6805950103`
- RevenueCat entitlement: `Caffeine+`

## Architecture

HealthKit dietary caffeine is the durable shared record. App entries are saved
as `HKQuantitySample` values in milligrams. A denied or unavailable HealthKit
write falls back to `LocalCaffeineEntry`, which the originating device retries
later. SwiftData is a read-through cache for widgets and complications.

The phone sends settings to the watch with WatchConnectivity. It does not queue
intake entries because HealthKit synchronizes those records.

The calculation layer is pure Swift in
`Shared/Utilities/CaffeineClearance.swift`. It owns remaining-dose calculations,
bedtime forecasts, half-life ranges, source reconciliation, daily summaries,
and latest modeled drink times. Keep model tests independent of HealthKit and
SwiftUI.

Key files:

- `Shared/Utilities/CaffeineClearance.swift`
- `Shared/Services/HealthKitService.swift`
- `Shared/Services/CaffeineLogService.swift`
- `Shared/Services/WatchSyncService.swift`
- `Shared/Services/StoreService.swift`
- `Caffeine/Views/CaffeineViews.swift`

## Access model

Logging, previewing a dose, current and bedtime estimates, Apple Health source
controls, widgets, complications, and seven days of history are free.

Caffeine+ unlocks full history and trends, editable quick-preview amounts, and
the bedtime reminder. A lapsed subscriber keeps saved preset values, but cannot
edit them until access is restored.

Store products:

- `com.jackwallner.caffeine.monthly`, $5.99 with a one-week trial
- `com.jackwallner.caffeine.yearly`, $29.99 with a one-week trial
- `com.jackwallner.caffeine.pro.lifetime`, $59.99

## App Review constraints

- Never describe a modeled estimate as a measurement of caffeine in the body.
- Never claim that a displayed time guarantees sleep or safety.
- Use `may remain`, `modeled`, `estimate`, and `preference` consistently.
- Do not include prices, `free`, or discounts in screenshots or screenshot headers.
- App Store name: `Caffeine Tracker: Bedtime`.
- Subtitle: `Preview What's Left Tonight`.
- Keywords: `coffee,intake,calculator,sleep,cutoff,half-life,energy,drink,log,timer,metabolism,widget,watch,mg`.

## Release

Run `xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh`. App Store scripts target ASC app `6805950103`.
The rejected Protein app has ASC ID `6797089333` and must not be reused for this
submission.
