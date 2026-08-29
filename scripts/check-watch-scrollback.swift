import Foundation

// Two properties of the watch terminal that cannot be checked by running it — a view is
// needed for that — but that CAN be checked against the sources, and that both regress
// invisibly:
//
//   1. How much scrollback the watch asks for, versus what a WatchConnectivity message
//      can actually carry. The relay path encodes the same capture into
//      `updateApplicationContext`, capped at 262,144 bytes and throwing SILENTLY past it
//      (iOS/PhoneConnectivity.swift records the failure; the wrist shows nothing). So the
//      number is bounded on both sides: too small and there is nothing to scroll back
//      through, too large and the relay dies without a symptom.
//   2. That every auto-scroll-to-tail is gated on `followTail`. An ungated one re-breaks
//      "scrolling back gets yanked to the bottom" within one 1.5s poll, and it re-breaks
//      it invisibly: the view still looks right whenever output happens to be idle.
@main
struct CheckWatchScrollback {

    /// WatchConnectivity's documented application-context limit.
    static let wcCapBytes = 262_144
    /// A 600px screen-peek JPEG rides the *same* snapshot as the watched output
    /// (iOS/MeshStore.swift builds both into one MeshSnapshot), and JSONEncoder base64s
    /// Data, so ~80KB of JPEG costs ~110KB on the wire.
    static let screenPeekBytes = 110_000
    /// Machines, sessions, events, usage, quick commands — the rest of the snapshot.
    static let snapshotOverheadBytes = 25_000
    /// Worst-case bytes per captured line: a wide Mac pane is ~200 columns, and JSON
    /// escaping of a TUI's punctuation inflates that.
    static let bytesPerLine = 220

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    static func main() {
        checkScrollbackFitsTheRelay()
        checkEveryAutoFollowIsGated()
        print("check-watch-scrollback: OK")
    }

    static func source(_ rel: String) -> String {
        guard let s = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8) else {
            fatalError("cannot read \(rel)")
        }
        return s
    }

    /// The `lines:` argument of the `output(agent:lines:…)` call in a source file.
    static func requestedLines(_ rel: String) -> Int {
        let text = source(rel)
        guard let r = text.range(of: #"output\(agent: [A-Za-z.]+, lines: [0-9]+"#,
                                 options: .regularExpression),
              let digits = text[r].split(separator: " ").last,
              let n = Int(digits) else {
            fatalError("no output(agent:lines:) call found in \(rel)")
        }
        return n
    }

    static func checkScrollbackFitsTheRelay() {
        let watchLines = requestedLines("Watch/WatchMeshStore.swift")
        let phoneLines = requestedLines("iOS/MeshStore.swift")

        // A watch screen shows roughly 20 monospaced lines at the default 13pt. Under 150
        // lines is under 8 screens — not enough to scroll back through a build log, which
        // is the complaint this lower bound exists to keep fixed.
        assert(watchLines >= 150,
               "watch scrollback is \(watchLines) lines — too shallow to read back through")

        for (label, lines) in [("watch direct", watchLines), ("phone relay", phoneLines)] {
            let worstCase = lines * bytesPerLine + screenPeekBytes + snapshotOverheadBytes
            assert(worstCase < wcCapBytes,
                   "\(label) asks for \(lines) lines: worst-case snapshot is \(worstCase) bytes, over the \(wcCapBytes)-byte WatchConnectivity cap that throws silently")
        }
        print("check-watch-scrollback: \(watchLines) lines direct, \(phoneLines) relayed, both inside the 262,144-byte cap")
    }

    static func checkEveryAutoFollowIsGated() {
        let views = source("Watch/WatchViews.swift")
        let marker = "onChange(of: store.output)"
        var searched = views.startIndex
        var gated = 0
        while let hit = views.range(of: marker, range: searched..<views.endIndex) {
            let body = views[hit.upperBound...].prefix(400)
            assert(body.contains(#"proxy.scrollTo("tail""#),
                   "unexpected \(marker) handler: this check assumes each one auto-follows the tail")
            assert(body.contains("guard followTail else { return }"),
                   "an \(marker) handler scrolls on every poll without checking followTail — manual scroll-back will be yanked to the bottom again")
            gated += 1
            searched = hit.upperBound
        }
        // Reader and Raw. If a third terminal appears it must be gated too, so fail loudly
        // rather than quietly checking only the two that existed when this was written.
        assert(gated == 2, "expected 2 auto-following terminals, found \(gated)")

        // followTail must start true, or a freshly opened terminal never follows at all.
        assert(views.contains("@State private var followTail = true"),
               "followTail must default to true so an opened terminal follows until the reader scrolls away")
        print("check-watch-scrollback: \(gated) terminals auto-follow only while the reader is at the bottom")
    }
}
