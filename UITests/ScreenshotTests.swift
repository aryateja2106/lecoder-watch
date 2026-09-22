// ScreenshotTests.swift — walks the iPhone app's screens and attaches a named screenshot of each, so docs/product/shots/*.png are real captures of the current build, never mocks.
//
// Off by default (the smoke gate must stay fast): runs only when the test runner's
// environment carries MESH_SHOTS=1 —
//   TEST_RUNNER_MESH_SHOTS=1 xcodebuild test -only-testing:MeshWatchUITests/ScreenshotTests \
//     -resultBundlePath build/shots.xcresult …
//   xcrun xcresulttool export attachments --path build/shots.xcresult --output-path docs/product/shots
// Each attachment is named after the file it becomes (iphone-<screen>.png); the exporter
// writes a manifest, and scripts/product-shots.sh renames by that manifest.
import XCTest

final class ScreenshotTests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let att = XCTAttachment(screenshot: app.screenshot())
        att.name = "iphone-\(name).png"
        att.lifetime = .keepAlways
        add(att)
    }

    func testEveryScreenIsCaptured() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MESH_SHOTS"] == "1", "set TEST_RUNNER_MESH_SHOTS=1 to capture screenshots")
        let app = XCUIApplication()
        app.launchArguments += ["-mesh.requireBiometrics.v1", "<false/>"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(2)

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        for name in ["Machines", "Terminal", "Apps"] {
            let tab = tabs.buttons[name]
            guard tab.waitForExistence(timeout: 5) else { continue }
            tab.tap(); sleep(2)
            shoot(app, name.lowercased())
        }

        // The bell: alerts, usage and the event log, one tap from any tab.
        let bell = app.buttons["Monitor"].firstMatch
        if bell.waitForExistence(timeout: 3) {
            bell.tap(); sleep(2); shoot(app, "monitor")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() }
        }

        let settings = tabs.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap(); sleep(2)
        shoot(app, "settings")

        let report = app.buttons["Report a problem"].firstMatch
        if report.waitForExistence(timeout: 5) {
            report.tap(); sleep(2); shoot(app, "report-a-problem")
            app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
        }
        let account = app.buttons["Sign in or create an account"].firstMatch
        if account.waitForExistence(timeout: 3) {
            account.tap(); sleep(2); shoot(app, "account")
            app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
        }
        let guides = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Guides'")).firstMatch
        if guides.waitForExistence(timeout: 3) {
            guides.tap(); sleep(2); shoot(app, "guides")
            app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
        }
        let pair = app.buttons["Pair a machine"].firstMatch
        if pair.waitForExistence(timeout: 3) {
            if !pair.isHittable { app.swipeUp() }
            pair.tap(); sleep(2); shoot(app, "pair")
        }
    }
}
