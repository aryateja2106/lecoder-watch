import XCTest

/// End-to-end check of the goal's "tapping opens the session": post a real event to
/// the live Mac daemon, let the app poll /events and raise the banner, tap the banner,
/// and assert we land on that session. Headless — no human finger needed.
final class NotificationTapUITests: XCTestCase {
    // Set MESHD_URL (e.g. http://100.x.y.z:8899/events?token=YOUR_TOKEN) in the test scheme's
    // environment to run this end-to-end against a live daemon; defaults to localhost.
    private let daemon = ProcessInfo.processInfo.environment["MESHD_URL"] ?? "http://127.0.0.1:8899/events"
    private let testSession = "uitest-open"

    func testNotificationTapOpensSession() throws {
        let app = XCUIApplication()
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Grant notification permission if the prompt appears.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        // Let the first poll seed existing daemon events silently (so ours is "new").
        sleep(12)

        // Producer's exact shape: a needs-input event for our test session.
        postEvent(level: "needs-input", title: "Permission needed",
                  body: "Allow edit to UITest.swift?", session: testSession)

        // The next poll (≤8s) fires the banner. Catch + tap it.
        let banner = waitForBanner(springboard, timeout: 22)
        XCTAssertNotNil(banner, "notification banner never appeared\n\(springboard.debugDescription)")
        banner?.tap()

        // didReceive → openSession → Terminal tab → navigationDestination opens the session.
        XCTAssertTrue(app.navigationBars[testSession].waitForExistence(timeout: 10),
                      "tapping the notification did not open session \(testSession)\n\(app.debugDescription)")
    }

    /// Try a few known ways to locate the banner across iOS versions.
    private func waitForBanner(_ springboard: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let candidates = [
            springboard.otherElements["NotificationShortLookView"],
            springboard.staticTexts["Claude needs input"],
            springboard.otherElements.containing(.staticText, identifier: "Claude needs input").element,
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for c in candidates where c.exists && c.isHittable { return c }
            _ = candidates[0].waitForExistence(timeout: 1)
        }
        return candidates.first { $0.exists }
    }

    private func postEvent(level: String, title: String, body: String, session: String) {
        var req = URLRequest(url: URL(string: daemon)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "source": "claude", "level": level, "title": title, "body": body, "session": session,
        ])
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 6)
    }
}
