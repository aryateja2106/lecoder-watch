import XCTest

/// The check that would have caught the 0.5.0 crash.
///
/// 0.5.0 shipped `UITextField.appearance().smartQuotesType = .no`. It compiled, it
/// passed every static check in scripts/, and it killed the app the moment any screen
/// containing a TextField was shown — because UIKit replays a stored appearance
/// invocation onto each field entering a window, and replaying a UITextInputTraits
/// setter onto a UITextField throws.
///
/// Nothing that reads source could see that. The only thing that catches it is running
/// the app and putting a text field on screen, which is all this does.
final class SmokeTests: XCTestCase {

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        // The biometric gate cannot be satisfied on a simulator with no enrolled face,
        // and it is not what this test is about.
        // The `<false/>` plist literal is what makes the argument domain yield a real
        // Bool; a bare "NO" arrives as a String and `object(forKey:) as? Bool` returns nil.
        app.launchArguments += ["-mesh.requireBiometrics.v1", "<false/>"]
        app.launch()
        return app
    }

    /// Every tab must survive being shown. The Settings tab is the one that holds the
    /// machine editor — a List of TextFields — so it is the one that used to die.
    func testEveryTabSurvives() {
        let app = launchedApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "app never reached the foreground")

        for name in ["Machines", "Terminal", "Remote", "Monitor", "Settings"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "no \(name) tab")
            tab.tap()
            // `app.state == .runningForeground` alone is NOT enough: XCUITest brings a
            // crashed app straight back up, so the state reads healthy either way. It
            // comes back on the FIRST tab though, having lost its selection — measured,
            // by reintroducing the 0.5.0 crash and watching this assertion be the only
            // one in this test that could tell.
            XCTAssertTrue(tab.isSelected,
                          "the \(name) tab is not selected after tapping it — the app most likely crashed and relaunched")
            XCTAssertEqual(app.state, .runningForeground, "the app died on the \(name) tab")
        }
    }

    /// A text field must be able to appear. This is the exact shape of the shipped crash:
    /// a UITextField entering a window.
    func testATextFieldCanAppear() {
        let app = launchedApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        // The machine editor's fields live here. If none is reachable the test has
        // stopped testing anything, so say so rather than passing quietly.
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "no text field on Settings — this test no longer covers the crash it exists for")
        XCTAssertEqual(app.state, .runningForeground, "the app died showing a text field")
    }

    /// The pairing sheet is a modal presentation full of text fields — the precise path
    /// the user hit when they tapped the button next to it.
    func testPairSheetOpens() {
        let app = launchedApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // Two screens offer this button (the empty Machines tab and Settings); either
        // one exercises the same sheet.
        let pair = app.buttons["Pair a machine"].firstMatch
        guard pair.waitForExistence(timeout: 10) else {
            XCTFail("no 'Pair a machine' button — the pairing entry point moved")
            return
        }
        pair.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10),
                      "the pairing sheet showed no text fields")
        XCTAssertEqual(app.state, .runningForeground, "the app died presenting the pairing sheet")
    }
}
