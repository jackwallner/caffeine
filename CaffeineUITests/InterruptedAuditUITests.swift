import XCTest

/// Audit evidence for a user who is interrupted mid-task and comes back later.
/// Each flow either backgrounds the app (home button, then activate) or kills
/// it (terminate, then launch) and records what survived. It attaches
/// screenshots and a text log and never asserts on copy.
final class InterruptedAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var notes: [String] = []
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.caffeine")
    }

    override func tearDown() {
        let note = XCTAttachment(string: notes.joined(separator: "\n"))
        note.name = "interrupted-notes.txt"
        note.lifetime = .keepAlways
        add(note)
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        step += 1
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%02d-%@", step, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func note(_ text: String) { notes.append(text) }

    private func drip() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preview Drip'")).firstMatch
    }

    private func logButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch
    }

    @discardableResult
    private func tap(_ element: XCUIElement, wait: TimeInterval = 8) -> Bool {
        guard element.waitForExistence(timeout: wait) else {
            note("MISSING: \(element.debugDescription.prefix(120))")
            return false
        }
        element.tap()
        return true
    }

    private func background(seconds: UInt32 = 3) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
        app.activate()
        sleep(2)
    }

    private func relaunch(_ extra: [String] = []) {
        app.terminate()
        sleep(1)
        app.launchArguments = extra
        app.launch()
        sleep(3)
    }

    private func finishOnboardingWithoutHealth() {
        tap(app.buttons["Get started"])
        sleep(1)
        tap(app.buttons["Continue"])
        sleep(1)
        tap(app.buttons["Not now"])
        sleep(1)
        tap(app.buttons["Skip for now"])
        sleep(3)
        tap(app.buttons["Continue with the free app"])
        sleep(2)
    }

    // MARK: - Flows

    /// Interrupted halfway through onboarding. Background first, then a kill.
    func test1_OnboardingInterrupted() {
        app.launchArguments = ["-hasCompletedSetup", "NO"]
        app.launch()
        sleep(2)
        tap(app.buttons["Get started"])
        sleep(1)
        tap(app.buttons["Continue"])
        sleep(1)
        snap("at-health-step")
        note("Reached step 3 of 5 (Health).")

        background()
        snap("health-step-after-background")
        note("After home + activate: Connect button exists = \(app.buttons["Connect Apple Health"].exists)")

        relaunch(["-hasCompletedSetup", "NO"])
        snap("after-kill-relaunch")
        note("After kill + relaunch: Get started exists = \(app.buttons["Get started"].exists), Connect exists = \(app.buttons["Connect Apple Health"].exists)")
        let progress = app.progressIndicators.firstMatch
        note("Progress value after relaunch = \(progress.exists ? String(describing: progress.value) : "none")")

        // Relaunch WITHOUT forcing the flag off: did the app treat setup as done?
        relaunch()
        snap("after-kill-relaunch-no-flag")
        note("Relaunch without the forcing flag: Get started exists = \(app.buttons["Get started"].exists), Now tab exists = \(app.tabBars.buttons["Now"].exists)")
    }

    /// Drink preview sheet edited, then the app is interrupted.
    func test2_PreviewSheetInterrupted() {
        app.launchArguments = ["-hasCompletedSetup", "NO"]
        app.launch()
        sleep(2)
        finishOnboardingWithoutHealth()
        snap("now-empty")

        tap(drip())
        sleep(2)
        let slider = app.sliders.firstMatch
        if slider.exists { slider.adjust(toNormalizedSliderPosition: 0.8) }
        sleep(1)
        snap("preview-edited")
        note("Preview slider value after edit = \(slider.exists ? String(describing: slider.value) : "none")")
        note("Log button label = \(logButton().exists ? logButton().label : "none")")

        background(seconds: 5)
        snap("preview-after-background")
        note("After background: slider exists = \(app.sliders.firstMatch.exists), value = \(app.sliders.firstMatch.exists ? String(describing: app.sliders.firstMatch.value) : "none"), Log label = \(logButton().exists ? logButton().label : "none")")

        relaunch()
        snap("after-kill-relaunch")
        note("After kill: sheet slider exists = \(app.sliders.firstMatch.exists), Now tab exists = \(app.tabBars.buttons["Now"].exists), Drip chip exists = \(drip().exists)")
    }

    /// Log a drink, get interrupted, come back, look for undo and the entry.
    func test3_LogThenInterrupted() {
        app.launchArguments = ["-hasCompletedSetup", "NO"]
        app.launch()
        sleep(2)
        finishOnboardingWithoutHealth()

        tap(drip())
        sleep(1)
        tap(logButton())
        sleep(3)
        snap("just-logged")
        note("Right after log: Undo exists = \(app.buttons["Undo"].exists), Retry now exists = \(app.buttons["Retry now"].exists)")

        background(seconds: 130)
        snap("back-after-130s")
        note("After 130 s in background: Undo exists = \(app.buttons["Undo"].exists)")

        relaunch()
        snap("after-kill-relaunch")
        note("After kill: Undo exists = \(app.buttons["Undo"].exists), Retry now exists = \(app.buttons["Retry now"].exists)")
        app.swipeUp()
        sleep(1)
        snap("after-kill-scrolled")
    }

    /// Tab, scroll position and Timeline range after a kill, and Timeline
    /// freshness after logging elsewhere.
    func test4_TabStateAndTimelineFreshness() {
        app.launchArguments = ["-hasCompletedSetup", "NO"]
        app.launch()
        sleep(2)
        finishOnboardingWithoutHealth()

        app.tabBars.buttons["Timeline"].tap()
        sleep(3)
        snap("timeline-before-log")
        app.tabBars.buttons["Now"].tap()
        sleep(1)
        tap(drip())
        sleep(1)
        tap(logButton())
        sleep(3)
        app.tabBars.buttons["Timeline"].tap()
        sleep(3)
        snap("timeline-after-log")

        app.segmentedControls.buttons["30D"].tap()
        sleep(2)
        snap("timeline-30d")
        relaunch()
        snap("after-kill-relaunch")
        note("After kill from Timeline/30D: Now selected = \(app.tabBars.buttons["Now"].isSelected), Timeline selected = \(app.tabBars.buttons["Timeline"].isSelected)")
    }
}
