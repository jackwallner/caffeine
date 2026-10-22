import XCTest

/// Walks the app the way a first-time user would, attaching a screenshot at each
/// step and a text log of tap-target sizes. This is audit evidence, not a
/// regression suite: it records what is on screen and never asserts on copy.
final class NewcomerAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var targetLog: [String] = []
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.caffeine")
    }

    override func tearDown() {
        let note = XCTAttachment(string: targetLog.joined(separator: "\n"))
        note.name = "tap-targets.txt"
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

    private func measure(_ label: String, _ element: XCUIElement) {
        guard element.exists else {
            targetLog.append("\(label): not found")
            return
        }
        let f = element.frame
        targetLog.append(String(format: "%@: %.0fx%.0f at (%.0f,%.0f) hittable=%@",
                                label, f.width, f.height, f.minX, f.minY, element.isHittable ? "yes" : "no"))
    }

    private func any(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @discardableResult
    private func tap(_ element: XCUIElement, wait: TimeInterval = 8) -> Bool {
        guard element.waitForExistence(timeout: wait) else {
            targetLog.append("MISSING: \(element.debugDescription.prefix(120))")
            return false
        }
        element.tap()
        return true
    }

    /// Answers the system Health sheet by tapping whichever grant control is up.
    private func grantHealthSheet() {
        for _ in 0..<5 {
            sleep(2)
            snap("health-sheet")
            let turnOn = any("Turn On All")
            if turnOn.exists { turnOn.tap(); sleep(1) }
            let allow = app.buttons["Allow"]
            if allow.exists { allow.tap(); return }
            let next = app.buttons["Next"]
            if next.exists { next.tap(); continue }
            if app.buttons["Connect Apple Health"].exists { return }
            if app.staticTexts["Not now"].exists { return }
        }
    }

    // MARK: - Flows

    /// Fresh install, grant everything, log a first drink, visit every tab.
    func test1_FirstRunGrantAndLog() {
        app.launch()
        sleep(2)
        snap("welcome")
        measure("Get started", app.buttons["Get started"])
        tap(app.buttons["Get started"])

        sleep(1)
        snap("bedtime")
        measure("Continue", app.buttons["Continue"])
        tap(app.buttons["Continue"])

        sleep(1)
        snap("health-explainer")
        measure("Not now (health)", app.buttons["Not now"])
        measure("Connect Apple Health", app.buttons["Connect Apple Health"])
        tap(app.buttons["Connect Apple Health"])
        grantHealthSheet()

        sleep(2)
        snap("body-explainer")
        measure("Skip for now (body)", app.buttons["Skip for now"])
        tap(app.buttons["Skip for now"])

        sleep(3)
        snap("plus-step")
        measure("Continue with the free app", app.buttons["Continue with the free app"])
        measure("Restore (onboarding)", app.buttons["Restore"])
        measure("Terms (onboarding)", app.links["Terms of Use"])
        tap(app.buttons["Continue with the free app"])

        sleep(2)
        snap("now-empty")
        measure("Refresh", app.buttons["Refresh"])
        measure("Settings gear", app.buttons["Settings"])
        measure("Drip coffee quick add", app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preview Drip'")).firstMatch)

        // First action: the one-tap log a newcomer expects.
        let drip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preview Drip'")).firstMatch
        tap(drip)
        sleep(2)
        snap("preview-sheet")
        measure("Log button", app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch)
        measure("Cancel", app.buttons["Cancel"])
        measure("Dose slider", app.sliders.firstMatch)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch)

        sleep(3)
        snap("now-after-log")
        measure("Undo", app.buttons["Undo"])
        tap(app.buttons["Undo"], wait: 3)
        sleep(2)
        snap("now-after-undo")

        // Log again so later tabs have an entry.
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preview Drip'")).firstMatch)
        sleep(1)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch)
        sleep(3)
        app.swipeUp()
        snap("now-scrolled")

        // Provenance sheet.
        app.swipeDown()
        let provenance = app.buttons["Where this estimate comes from"]
        measure("Provenance row", provenance)
        if tap(provenance, wait: 3) {
            sleep(1)
            snap("breakdown-sheet")
            tap(app.buttons["Done"], wait: 3)
        }

        app.tabBars.buttons["Cutoff"].tap()
        sleep(2)
        snap("cutoff-tab")
        measure("Cutoff connect", app.buttons["Connect Apple Health"])

        app.tabBars.buttons["Timeline"].tap()
        sleep(3)
        snap("timeline-7d")
        app.segmentedControls.buttons["30D"].tap()
        sleep(2)
        snap("timeline-30d-locked")

        app.tabBars.buttons["Upgrade"].tap()
        sleep(3)
        snap("upgrade-tab")
        measure("Restore (paywall)", app.buttons["Restore purchases"])

        app.tabBars.buttons["Now"].tap()
        sleep(1)
        tap(app.buttons["Settings"])
        sleep(2)
        snap("settings-top")
        app.swipeUp()
        snap("settings-mid")
        app.swipeUp()
        snap("settings-bottom")
    }

    /// The newcomer who taps "Not now" on Health and then logs anyway.
    func test2_SkipHealthThenLog() {
        app.launchArguments += ["-OnboardingStep", "2"]
        app.launch()
        sleep(2)
        snap("health-step-direct")
        tap(app.buttons["Not now"])
        sleep(1)
        tap(app.buttons["Skip for now"])
        sleep(3)
        tap(app.buttons["Continue with the free app"])
        sleep(2)
        snap("now-no-health")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preview Drip'")).firstMatch)
        sleep(1)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch)
        sleep(3)
        snap("now-logged-no-health")
        app.swipeUp()
        sleep(1)
        snap("now-logged-no-health-scrolled")
        app.swipeDown()
        tap(app.buttons["Retry now"], wait: 3)
        sleep(2)
        snap("after-retry")
    }

    /// Largest accessibility text size through onboarding.
    func test3_LargeTextOnboarding() {
        app.launchArguments += [
            "-OnboardingStep", "0",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
        ]
        app.launch()
        sleep(2)
        snap("large-welcome")
        tap(app.buttons["Get started"])
        sleep(1)
        snap("large-bedtime")
        tap(app.buttons["Continue"])
        sleep(1)
        snap("large-health")
        measure("Large: Connect Apple Health", app.buttons["Connect Apple Health"])
    }
}
