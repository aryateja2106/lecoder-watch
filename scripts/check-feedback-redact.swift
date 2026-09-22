// check-feedback-redact.swift — the problem report never carries a secret: every key shape the daemon's redactor knows is replaced by its kind before the report exists.
//
// Pure. The patterns live in iOS/FeedbackView.swift (UIKit-bound view file), so this check
// carries the same table and asserts the two agree — the daemon-side twin is
// check-redact.sh over redact.ts.
import Foundation

@main struct CheckFeedbackRedact {
    static func main() throws {
        // The view file is found from this source file's own location (check-all.sh runs the
        // compiled binary from whatever directory it was called in); an argument overrides.
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let file = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : here.appendingPathComponent("iOS/FeedbackView.swift").path
        let source = try String(contentsOfFile: file, encoding: .utf8)
        // Pull the (pattern, label) rows out of the view file so the table under test is the shipped one.
        let rowPattern = try NSRegularExpression(pattern: ##"\(#"(.+?)"#, "([^"]+)"\)"##)
        let rows = rowPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { m -> (String, String) in
            (String(source[Range(m.range(at: 1), in: source)!]), String(source[Range(m.range(at: 2), in: source)!]))
        }
        guard rows.count >= 6 else { fail("expected the redaction table in iOS/FeedbackView.swift, found \(rows.count) rows") }
        func redact(_ text: String) -> String {
            var s = text
            for (pattern, label) in rows { s = s.replacingOccurrences(of: pattern, with: label, options: .regularExpression) }
            return s
        }
        let samples: [(String, String)] = [
            ("token sk-abcdefghijklmnopqrstuvwxyz1234 here", "sk-abcdefghijklmnopqrstuvwxyz1234"),
            ("gateway vck_06XKm7nltbMFbpQUKaBTHaMPRZQ6Dc", "vck_06XKm7nltbMFbpQUKaBTHaMPRZQ6Dc"),
            ("gh ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"),
            ("Authorization: Bearer 19f88756bc17f50ba50d62266cb51976", "19f88756bc17f50ba50d62266cb51976"),
            ("mesh token 19f88756bc17f50ba50d62266cb51976c2572224bbd96f30c38be85a378f951e", "19f88756bc17f50ba50d62266cb51976c2572224bbd96f30c38be85a378f951e"),
            ("aws AKIAIOSFODNN7EXAMPLE", "AKIAIOSFODNN7EXAMPLE"),
        ]
        for (text, secret) in samples {
            let out = redact(text)
            if out.contains(secret) { fail("secret survived redaction: \(out)") }
        }
        let plain = "Claude needs your permission — date > /tmp/x"
        if redact(plain) != plain { fail("plain text was altered: \(redact(plain))") }
        print("check-feedback-redact: OK — \(rows.count) patterns, \(samples.count) secrets removed, plain text untouched")
    }
    static func fail(_ m: String) -> Never { print("check-feedback-redact: FAIL — \(m)"); exit(1) }
}
