import Foundation

/// Pins the compact-watch width cutoff so a layout tweak on a 45mm simulator does not
/// silently flip every 44mm user between chrome levels.
@main
struct CheckWatchScreen {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    static func main() {
        let text = source("Watch/WatchScreen.swift")
        assert(text.contains("compactWidthCutoff: CGFloat = 190"),
               "compactWidthCutoff must stay 190pt — 45mm is 198pt, 41mm is 176pt")
        assert(text.contains("screenBounds.width < compactWidthCutoff"),
               "isCompact must compare against compactWidthCutoff")
        assert(text.contains("providerMark(for agentType:"),
               "provider marks live in WatchScreen for compact rows")
        print("check-watch-screen: OK (cutoff 190pt, <45mm class)")
    }

    static func source(_ rel: String) -> String {
        guard let s = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8) else {
            fatalError("cannot read \(rel)")
        }
        return s
    }
}
