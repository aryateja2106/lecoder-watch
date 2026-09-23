// FeedbackSendTests.swift — the publish proof, driven through the real UI: create an account, then send one report from Settings → Report a problem and read the "Sent. Reference …" line back.
//
// Off by default: it writes a real row to Supabase (and, ten minutes later, a real GitHub
// issue), so it runs only when the test runner's environment carries
// MESH_FEEDBACK_E2E=1 — `TEST_RUNNER_MESH_FEEDBACK_E2E=1 xcodebuild test
// -only-testing:MeshWatchUITests/FeedbackSendTests …`. In every other run (the smoke
// gate) it is skipped, so gates never spam the feedback table.
//
// The account e-mail and the report title carry a timestamp so the row and the auth user
// are findable afterwards; the reference printed by the app is the row id's first 8 chars.
import XCTest

final class FeedbackSendTests: XCTestCase {
    func testCreateAccountAndSendOneReport() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["MESH_FEEDBACK_E2E"] == "1", "set TEST_RUNNER_MESH_FEEDBACK_E2E=1 to send a real report")
        let stamp = Int(Date().timeIntervalSince1970)
        let email = "check-published+app\(stamp)@lesearch.ai"
        let password = "e2e-" + UUID().uuidString.prefix(16)

        let app = XCUIApplication()
        app.launchArguments += ["-mesh.requireBiometrics.v1", "<false/>"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        // 1. Account: a fresh e-mail through the same form a user sees. A previous run
        // leaves this simulator signed in (the Keychain survives a signed reinstall), so
        // sign out first when the row says so.
        let signOut = app.buttons["Sign out"].firstMatch
        if signOut.waitForExistence(timeout: 3) { signOut.tap(); sleep(2) }
        let signIn = app.buttons["Sign in or create an account"].firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "Account section missing from Settings")
        signIn.tap()
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap(); emailField.typeText(email)
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap(); passwordField.typeText(String(password))
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.staticTexts["Signed in"].waitForExistence(timeout: 30), "signup did not come back signed in")
        // iOS offers to save the new password in a system sheet over the app; decline it.
        // The sheet is hosted inside the app's own accessibility tree (a remote view).
        let notNow = app.buttons["Not Now"].firstMatch
        if notNow.waitForExistence(timeout: 5) { notNow.tap(); sleep(1) }

        // 2. The report.
        let report = app.buttons["Report a problem"].firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        // The Account screen is still sliding away right after signup; a tap during the
        // transition lands on nothing, so tap until the report screen's bar is up.
        for _ in 0..<3 where !app.navigationBars["Report a problem"].exists {
            sleep(1); report.tap()
            _ = app.navigationBars["Report a problem"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.navigationBars["Report a problem"].exists, "Report a problem did not open")
        // Title first (single-line), then the multi-line note. Typing goes through
        // app.typeText — to the first responder — because typeText on the vertical
        // TextField element itself reported success while the field stayed empty
        // (iOS 27 simulator, SwiftUI TextField(axis: .vertical)).
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        // Tap until the field itself reports focus: right after the screen pushes, the
        // first tap sometimes lands before the form is interactive.
        for _ in 0..<5 where !(title.value(forKey: "hasKeyboardFocus") as? Bool ?? false) {
            title.tap(); sleep(1)
        }
        XCTAssertTrue(title.value(forKey: "hasKeyboardFocus") as? Bool ?? false, "Title field never took focus")
        app.typeText("Publish proof \(stamp): report sent from the app")
        // Do not assert on `title.value`: a focused SwiftUI TextField reports its
        // placeholder there on this runtime. The proof that the text landed is the row
        // Supabase holds afterwards, whose title carries this stamp.
        // The note is optional in the product, so nothing here asserts on it. Typing goes
        // through app.typeText (to the first responder): on the iOS 27 simulator a SwiftUI
        // TextField(axis: .vertical) reports its placeholder as `value` and typeText sent
        // to the element itself can miss, while typing to the first responder lands — the
        // text reached Supabase in the run that produced issues/1.
        let body = app.descendants(matching: .any)
            .matching(NSPredicate(format: "placeholderValue == %@", "What were you doing, and what did you expect?")).firstMatch
        if body.waitForExistence(timeout: 5) {
            body.tap(); sleep(1)
            app.typeText("Sent by UITests/FeedbackSendTests on a simulator as the end-to-end proof for PUBLISHED.md.")
            sleep(1)
        }
        let send = app.buttons["Send to LeSearch AI"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        if !send.isHittable { app.swipeUp() }
        send.tap()
        let sent = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Sent. Reference '")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 60), "no 'Sent. Reference' line — the report did not reach Supabase")
        // The line itself is the evidence; xcodebuild prints attachments' names, so the
        // reference is also written into an attachment for the log.
        let att = XCTAttachment(string: "email=\(email)\n\(sent.label)")
        att.lifetime = .keepAlways
        add(att)
        print("FEEDBACK_E2E email=\(email) \(sent.label)")
    }
}
